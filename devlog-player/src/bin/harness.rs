//! Visual harness: drive the real `App::render` offscreen via egui_kittest,
//! inject scripted input, dump PNGs Claude can read. Script is a sequence of
//! one-line commands on stdin or from a file path.
//!
//! Commands:
//!   step [N]            — run N frames (default 1)
//!   click X Y           — synthetic click at point
//!   drag X1 Y1 X2 Y2 [N]— drag with N intermediate steps (default 10)
//!   scroll X Y DX DY    — wheel at point: DY = zoom (positive = in), DX = pan
//!   key NAME            — press a named key (space/enter/escape/tab/left/right/up/down)
//!   playhead EPOCH      — set playhead (epoch seconds)
//!   select KIND IDX     — KIND ∈ {terminal,session,none}; IDX ignored for none
//!   view START END      — set the visible time window
//!   font SIZE           — set terminal font size
//!   playing 0|1         — toggle playback
//!   speed N             — set playback speed multiplier
//!   print_state         — log current selection/playhead/view
//!   list_sessions [N]   — log first N agent sessions with indices
//!   list_terminals [N]  — log first N terminals with indices
//!   snapshot PATH       — render current frame to PNG

use std::env;
use std::fs;
use std::io::Read;

use eframe::egui::{self, Key, Modifiers, PointerButton, Pos2};
use egui_kittest::Harness;

use devlog_player::app::{App, Selection};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let script: String = match env::args().nth(1).as_deref() {
        None | Some("-") => {
            let mut s = String::new();
            std::io::stdin().read_to_string(&mut s)?;
            s
        }
        Some(p) => fs::read_to_string(p)?,
    };

    eprintln!("loading app state...");
    let app = App::new();
    eprintln!(
        "  {} casts · {} sessions · t=[{:.0}..{:.0}]",
        app.metas.len(),
        app.sessions.len(),
        app.t_min,
        app.t_max
    );

    let mut harness = Harness::builder()
        .with_size(egui::vec2(1500.0, 950.0))
        .build_state(|ctx, app: &mut App| app.render(ctx), app);

    // Two warm-up frames so layout settles before any input.
    harness.run_steps(2);

    for (lineno, raw) in script.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Err(e) = run_cmd(&mut harness, line) {
            eprintln!("line {}: {} ({line})", lineno + 1, e);
        }
    }
    Ok(())
}

fn run_cmd(
    harness: &mut Harness<'_, App>,
    line: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut toks = line.split_whitespace();
    let cmd = toks.next().unwrap();
    let req = |t: Option<&str>, name: &str| -> Result<String, String> {
        t.map(str::to_owned).ok_or_else(|| format!("missing {name}"))
    };

    match cmd {
        "step" => {
            let n: usize = toks.next().and_then(|s| s.parse().ok()).unwrap_or(1);
            harness.run_steps(n);
        }
        "click" => {
            let x: f32 = req(toks.next(), "x")?.parse()?;
            let y: f32 = req(toks.next(), "y")?.parse()?;
            let pos = Pos2::new(x, y);
            push_pointer_moved(harness, pos);
            push_button(harness, pos, true);
            let _ = harness.run_ok();
            push_button(harness, pos, false);
            let _ = harness.run_ok();
        }
        "drag" => {
            let x1: f32 = req(toks.next(), "x1")?.parse()?;
            let y1: f32 = req(toks.next(), "y1")?.parse()?;
            let x2: f32 = req(toks.next(), "x2")?.parse()?;
            let y2: f32 = req(toks.next(), "y2")?.parse()?;
            let n: usize = toks.next().and_then(|s| s.parse().ok()).unwrap_or(10);
            let start = Pos2::new(x1, y1);
            push_pointer_moved(harness, start);
            push_button(harness, start, true);
            let _ = harness.run_ok();
            for i in 1..=n {
                let t = i as f32 / n as f32;
                let p = Pos2::new(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
                push_pointer_moved(harness, p);
                let _ = harness.run_ok();
            }
            push_button(harness, Pos2::new(x2, y2), false);
            let _ = harness.run_ok();
        }
        "scroll" => {
            let x: f32 = req(toks.next(), "x")?.parse()?;
            let y: f32 = req(toks.next(), "y")?.parse()?;
            let dx: f32 = req(toks.next(), "dx")?.parse()?;
            let dy: f32 = req(toks.next(), "dy")?.parse()?;
            let pos = Pos2::new(x, y);
            push_pointer_moved(harness, pos);
            let _ = harness.run_ok();
            harness.input_mut().events.push(egui::Event::MouseWheel {
                unit: egui::MouseWheelUnit::Line,
                delta: egui::Vec2::new(dx, dy),
                phase: egui::TouchPhase::Move,
                modifiers: Modifiers::NONE,
            });
            let _ = harness.run_ok();
        }
        "key" => {
            let name = req(toks.next(), "key name")?;
            let key = parse_key(&name).ok_or_else(|| format!("unknown key {name}"))?;
            harness.key_press(key);
            let _ = harness.run_ok();
        }
        "playhead" => {
            let e: f64 = req(toks.next(), "epoch")?.parse()?;
            harness.state_mut().playhead = e;
            let _ = harness.run_ok();
        }
        "select" => {
            let kind = req(toks.next(), "kind")?;
            let idx: usize = toks
                .next()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
            harness.state_mut().selection = match kind.as_str() {
                "terminal" => Selection::Terminal(idx),
                "session" => Selection::Session(idx),
                "none" => Selection::None,
                other => return Err(format!("bad select kind: {other}").into()),
            };
            let _ = harness.run_ok();
        }
        "view" => {
            let s: f64 = req(toks.next(), "start")?.parse()?;
            let e: f64 = req(toks.next(), "end")?.parse()?;
            let a = harness.state_mut();
            a.view_start = s;
            a.view_end = e;
            let _ = harness.run_ok();
        }
        "font" => {
            let s: f32 = req(toks.next(), "size")?.parse()?;
            harness.state_mut().font_size = s;
            let _ = harness.run_ok();
        }
        "playing" => {
            let v: u8 = req(toks.next(), "0|1")?.parse()?;
            harness.state_mut().playing = v != 0;
            let _ = harness.run_ok();
        }
        "speed" => {
            let v: f64 = req(toks.next(), "speed")?.parse()?;
            harness.state_mut().speed = v;
            let _ = harness.run_ok();
        }
        "print_state" => {
            let a = harness.state();
            let sel = match a.selection {
                Selection::None => "none".to_string(),
                Selection::Terminal(i) => format!("terminal[{i}]"),
                Selection::Session(i) => format!("session[{i}]"),
            };
            eprintln!(
                "state: playhead={:.0} view=[{:.0},{:.0}] sel={} playing={} speed={}×",
                a.playhead, a.view_start, a.view_end, sel, a.playing, a.speed
            );
        }
        "list_sessions" => {
            let n: usize = toks.next().and_then(|s| s.parse().ok()).unwrap_or(20);
            let a = harness.state();
            for (i, s) in a.sessions.iter().enumerate().rev().take(n) {
                let title = s.title.as_deref().unwrap_or("(untitled)");
                let proj = s
                    .cwd
                    .as_deref()
                    .and_then(|c| c.rsplit('/').next())
                    .unwrap_or("?");
                eprintln!(
                    "  session[{i}] [{proj}] {title} ({} prompts)",
                    s.prompts.len()
                );
            }
        }
        "list_terminals" => {
            let n: usize = toks.next().and_then(|s| s.parse().ok()).unwrap_or(30);
            let a = harness.state();
            for (i, m) in a.metas.iter().enumerate().rev().take(n) {
                eprintln!("  terminal[{i}] {} ({:.0}-{:.0})", m.label(), m.start, m.end);
            }
        }
        "snapshot" => {
            let path = req(toks.next(), "path")?;
            let img = harness.render().map_err(|e| format!("render: {e}"))?;
            img.save(&path)?;
            eprintln!("snapshot -> {path}");
        }
        other => return Err(format!("unknown cmd: {other}").into()),
    }
    Ok(())
}

fn push_pointer_moved(h: &mut Harness<'_, App>, pos: Pos2) {
    h.input_mut().events.push(egui::Event::PointerMoved(pos));
}

fn push_button(h: &mut Harness<'_, App>, pos: Pos2, pressed: bool) {
    h.input_mut().events.push(egui::Event::PointerButton {
        pos,
        button: PointerButton::Primary,
        pressed,
        modifiers: Modifiers::NONE,
    });
}

fn parse_key(s: &str) -> Option<Key> {
    use Key::*;
    Some(match s.to_lowercase().as_str() {
        "space" => Space,
        "enter" => Enter,
        "escape" | "esc" => Escape,
        "tab" => Tab,
        "left" => ArrowLeft,
        "right" => ArrowRight,
        "up" => ArrowUp,
        "down" => ArrowDown,
        _ => return None,
    })
}
