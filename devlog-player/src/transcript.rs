//! Parses Claude Code session transcripts (`~/.claude/projects/<slug>/*.jsonl`)
//! into timestamped agent sessions — the narrative spine of the devlog.
//!
//! Each file is one session. We keep human prompts and a flattened, timestamped
//! list of entries (prompt / assistant text / tool use) for the detail view.

use std::fs;
use std::path::Path;

use chrono::DateTime;
use serde_json::Value;

#[derive(Clone, PartialEq)]
pub enum Role {
    User,
    Assistant,
    Tool,
}

#[derive(Clone)]
pub struct AgentEvent {
    pub epoch: f64,
    pub role: Role,
    pub text: String,
}

pub struct AgentSession {
    pub session_id: String,
    pub title: Option<String>,
    pub cwd: Option<String>,
    pub git_branch: Option<String>,
    pub start: f64,
    pub end: f64,
    /// Human prompts only (the "what was I trying to do" markers).
    pub prompts: Vec<AgentEvent>,
    /// Everything, in order, for the session detail panel.
    pub events: Vec<AgentEvent>,
}

fn parse_ts(s: &str) -> Option<f64> {
    DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|d| d.timestamp_millis() as f64 / 1000.0)
}

/// Pull readable text out of an assistant `message.content` block list.
fn assistant_blocks(content: &[Value]) -> Vec<(Role, String)> {
    let mut out = Vec::new();
    for b in content {
        match b.get("type").and_then(Value::as_str) {
            Some("text") => {
                if let Some(t) = b.get("text").and_then(Value::as_str) {
                    if !t.trim().is_empty() {
                        out.push((Role::Assistant, t.to_string()));
                    }
                }
            }
            Some("tool_use") => {
                let name = b.get("name").and_then(Value::as_str).unwrap_or("tool");
                out.push((Role::Tool, format!("⚙ {name}")));
            }
            _ => {}
        }
    }
    out
}

pub fn parse_file(path: &Path) -> Option<AgentSession> {
    let text = fs::read_to_string(path).ok()?;

    let mut session = AgentSession {
        session_id: path
            .file_stem()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default(),
        title: None,
        cwd: None,
        git_branch: None,
        start: f64::INFINITY,
        end: f64::NEG_INFINITY,
        prompts: Vec::new(),
        events: Vec::new(),
    };

    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let o: Value = match serde_json::from_str(line) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let ty = o.get("type").and_then(Value::as_str).unwrap_or("");

        if let Some(t) = o.get("aiTitle").and_then(Value::as_str) {
            session.title = Some(t.to_string());
        }
        if session.cwd.is_none() {
            if let Some(c) = o.get("cwd").and_then(Value::as_str) {
                session.cwd = Some(c.to_string());
            }
        }
        if session.git_branch.is_none() {
            if let Some(g) = o.get("gitBranch").and_then(Value::as_str) {
                if !g.is_empty() {
                    session.git_branch = Some(g.to_string());
                }
            }
        }

        let epoch = o.get("timestamp").and_then(Value::as_str).and_then(parse_ts);
        let Some(epoch) = epoch else { continue };
        // Skip subagent sidechains so the spine is the main conversation.
        if o.get("isSidechain").and_then(Value::as_bool) == Some(true) {
            continue;
        }

        let msg = o.get("message");
        match ty {
            "user" => {
                // String content = a real human prompt; list content = tool
                // results echoed back, which we skip.
                if let Some(content) = msg.and_then(|m| m.get("content")) {
                    if let Some(s) = content.as_str() {
                        let s = s.trim();
                        // Drop command/system-injected pseudo-prompts.
                        if !s.is_empty() && !s.starts_with('<') {
                            let ev = AgentEvent {
                                epoch,
                                role: Role::User,
                                text: s.to_string(),
                            };
                            session.prompts.push(ev.clone());
                            session.events.push(ev);
                        }
                    }
                }
            }
            "assistant" => {
                if let Some(content) = msg.and_then(|m| m.get("content")).and_then(Value::as_array) {
                    for (role, text) in assistant_blocks(content) {
                        session.events.push(AgentEvent { epoch, role, text });
                    }
                }
            }
            _ => continue,
        }

        session.start = session.start.min(epoch);
        session.end = session.end.max(epoch);
    }

    if session.events.is_empty() || !session.start.is_finite() {
        return None;
    }
    Some(session)
}

/// Parse every transcript under a projects root (`~/.claude/projects`), across
/// all project subdirectories, sorted by start time.
pub fn load_all(projects_root: &Path) -> Vec<AgentSession> {
    let mut sessions = Vec::new();
    let Ok(dirs) = fs::read_dir(projects_root) else {
        return sessions;
    };
    for dir in dirs.flatten() {
        if !dir.path().is_dir() {
            continue;
        }
        let Ok(files) = fs::read_dir(dir.path()) else {
            continue;
        };
        for f in files.flatten() {
            let p = f.path();
            if p.extension().and_then(|e| e.to_str()) == Some("jsonl") {
                if let Some(s) = parse_file(&p) {
                    sessions.push(s);
                }
            }
        }
    }
    sessions.sort_by(|a, b| a.start.partial_cmp(&b.start).unwrap());
    sessions
}
