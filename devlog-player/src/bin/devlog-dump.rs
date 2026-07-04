//! Validation harness for the UI-agnostic backend: load the real casts, AW
//! sqlite, and Claude Code transcripts and print a unified-timeline summary.

use std::path::PathBuf;

use devlog_player::aw::{self, Lane};
use devlog_player::cast::Recording;
use devlog_player::transcript;

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").expect("HOME"))
}

fn fmt_epoch(e: f64) -> String {
    use chrono::{TimeZone, Utc};
    Utc.timestamp_opt(e as i64, 0)
        .single()
        .map(|d| d.format("%Y-%m-%d %H:%M:%SZ").to_string())
        .unwrap_or_else(|| format!("{e:.0}"))
}

fn main() {
    let home = home();

    // ---- casts ----
    println!("== asciinema recordings ==");
    let cast_dir = home.join("asciinema-sessions");
    let mut paths: Vec<PathBuf> = std::fs::read_dir(&cast_dir)
        .map(|rd| {
            rd.flatten()
                .map(|e| e.path())
                .filter(|p| p.extension().and_then(|e| e.to_str()) == Some("cast"))
                .collect()
        })
        .unwrap_or_default();
    paths.sort();
    for p in &paths {
        match Recording::load(p, 256 * 1024) {
            Ok(r) => println!(
                "  {:<24} {} -> {}  ({} events, {:.0}s)",
                r.label(),
                fmt_epoch(r.start_epoch()),
                fmt_epoch(r.end_epoch()),
                r.cast.events.len(),
                r.cast.duration(),
            ),
            Err(e) => println!("  {p:?}: load error: {e}"),
        }
    }

    // ---- ActivityWatch ----
    println!("\n== activitywatch ==");
    let db = home.join("activitywatch/activitywatch/aw-server-rust/sqlite.db");
    match aw::load(&db) {
        Ok(data) => {
            for (lane, name) in [
                (Lane::Window, "window"),
                (Lane::Web, "web"),
                (Lane::Afk, "afk"),
                (Lane::Workspace, "workspace"),
            ] {
                let evs = data.get(lane);
                println!("  {name:<10} {} events", evs.len());
                if let Some(last) = evs.last() {
                    let preview = last
                        .field("title")
                        .or_else(|| last.field("app"))
                        .or_else(|| last.field("status"))
                        .or_else(|| last.field("workspace"))
                        .unwrap_or("");
                    println!(
                        "             latest @ {}: {}",
                        fmt_epoch(last.start),
                        &preview.chars().take(70).collect::<String>()
                    );
                }
            }
        }
        Err(e) => println!("  aw load error: {e}"),
    }

    // ---- transcripts ----
    println!("\n== claude code sessions ==");
    let sessions = transcript::load_all(&home.join(".claude/projects"));
    println!("  {} sessions total", sessions.len());
    for s in sessions.iter().rev().take(12) {
        let proj = s
            .cwd
            .as_deref()
            .and_then(|c| c.rsplit('/').next())
            .unwrap_or("?");
        println!(
            "  {} [{}] {} prompts  {}",
            fmt_epoch(s.start),
            proj,
            s.prompts.len(),
            s.title.as_deref().unwrap_or("(untitled)"),
        );
    }
}
