//! The egui app: timeline + rails + center pane. Held in the lib (rather than
//! main.rs) so the visual harness can drive it offscreen with the same code
//! the real binary runs.

use std::collections::HashMap;
use std::path::PathBuf;
use std::time::Instant;

use chrono::{Local, TimeZone};
use eframe::egui::{self, Color32, RichText};

use crate::aw::{self, AwData, AwEvent, Lane};
use crate::cast::{cast_meta, CastMeta, Recording};
use crate::termview;
use crate::transcript::{self, AgentSession, Role};

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").expect("HOME"))
}

fn fmt_clock(epoch: f64) -> String {
    Local
        .timestamp_opt(epoch as i64, 0)
        .single()
        .map(|d| d.format("%a %d %b %H:%M:%S").to_string())
        .unwrap_or_default()
}

fn fmt_hm(epoch: f64) -> String {
    Local
        .timestamp_opt(epoch as i64, 0)
        .single()
        .map(|d| d.format("%H:%M").to_string())
        .unwrap_or_default()
}

/// Largest "nice" step (seconds) ≤ `target`. Targets ~8 ticks across the view.
fn nice_interval(target: f64) -> f64 {
    const NICE: &[f64] = &[
        1.0, 5.0, 10.0, 15.0, 30.0, 60.0, 300.0, 600.0, 900.0, 1800.0, 3600.0, 7200.0,
        14400.0, 21600.0, 43200.0, 86400.0, 172_800.0,
    ];
    *NICE
        .iter()
        .rev()
        .find(|&&n| n <= target)
        .unwrap_or(&NICE[0])
}

fn fmt_tick(epoch: f64, interval: f64) -> String {
    let Some(d) = Local.timestamp_opt(epoch as i64, 0).single() else {
        return String::new();
    };
    if interval >= 86400.0 {
        d.format("%a %d").to_string()
    } else if interval >= 3600.0 {
        d.format("%H:00").to_string()
    } else if interval >= 60.0 {
        d.format("%H:%M").to_string()
    } else {
        d.format("%H:%M:%S").to_string()
    }
}

fn color_for(label: &str) -> Color32 {
    let mut h: u32 = 2166136261;
    for b in label.bytes() {
        h = (h ^ b as u32).wrapping_mul(16777619);
    }
    let hue = (h % 360) as f32;
    let (r, g, b) = hsv(hue, 0.45, 0.75);
    Color32::from_rgb(r, g, b)
}

fn hsv(h: f32, s: f32, v: f32) -> (u8, u8, u8) {
    let c = v * s;
    let x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs());
    let m = v - c;
    let (r, g, b) = match h as u32 / 60 {
        0 => (c, x, 0.0),
        1 => (x, c, 0.0),
        2 => (0.0, c, x),
        3 => (0.0, x, c),
        4 => (x, 0.0, c),
        _ => (c, 0.0, x),
    };
    (
        ((r + m) * 255.0) as u8,
        ((g + m) * 255.0) as u8,
        ((b + m) * 255.0) as u8,
    )
}

#[derive(Clone, Copy, PartialEq)]
pub enum Selection {
    None,
    Terminal(usize),
    Session(usize),
}

pub struct App {
    pub metas: Vec<CastMeta>,
    pub loaded: HashMap<usize, Recording>,
    pub aw: AwData,
    pub sessions: Vec<AgentSession>,

    pub t_min: f64,
    pub t_max: f64,
    pub view_start: f64,
    pub view_end: f64,
    pub playhead: f64,

    pub playing: bool,
    pub speed: f64,
    pub last_tick: Option<Instant>,

    pub selection: Selection,
    pub font_size: f32,
}

impl App {
    pub fn new() -> App {
        let home = home();

        let cast_dir = home.join("asciinema-sessions");
        let mut metas: Vec<CastMeta> = std::fs::read_dir(&cast_dir)
            .map(|rd| {
                rd.flatten()
                    .map(|e| e.path())
                    .filter(|p| p.extension().and_then(|e| e.to_str()) == Some("cast"))
                    .filter_map(|p| cast_meta(p).ok())
                    .collect()
            })
            .unwrap_or_default();
        metas.sort_by(|a, b| a.start.partial_cmp(&b.start).unwrap());

        let aw = aw::load(&home.join("activitywatch/activitywatch/aw-server-rust/sqlite.db"))
            .unwrap_or(AwData {
                lanes: HashMap::new(),
            });
        let sessions = transcript::load_all(&home.join(".claude/projects"));

        let mut t_min = f64::INFINITY;
        let mut t_max = f64::NEG_INFINITY;
        for m in &metas {
            t_min = t_min.min(m.start);
            t_max = t_max.max(m.end);
        }
        for s in &sessions {
            t_min = t_min.min(s.start);
            t_max = t_max.max(s.end);
        }
        if !t_min.is_finite() {
            t_min = 0.0;
            t_max = 1.0;
        }

        // Open on the most-recently-ending terminal at its tail.
        let (mut latest_end, mut latest_idx) = (f64::NEG_INFINITY, None);
        for (i, m) in metas.iter().enumerate() {
            if m.end > latest_end {
                latest_end = m.end;
                latest_idx = Some(i);
            }
        }
        let (selection, playhead) = match latest_idx {
            Some(i) => (Selection::Terminal(i), latest_end),
            None => (Selection::None, t_max),
        };

        // Default to the last 4 hours, clamped to available data.
        let default_span = 4.0 * 3600.0;
        let view_start = (t_max - default_span).max(t_min);

        App {
            metas,
            loaded: HashMap::new(),
            aw,
            sessions,
            t_min,
            t_max,
            view_start,
            view_end: t_max,
            playhead,
            playing: false,
            speed: 30.0,
            last_tick: None,
            selection,
            font_size: 13.0,
        }
    }

    pub fn ensure_loaded(&mut self, idx: usize) -> &Recording {
        self.loaded.entry(idx).or_insert_with(|| {
            Recording::load(&self.metas[idx].path, 256 * 1024)
                .expect("load recording")
        })
    }

    fn x_to_epoch(&self, x: f32, left: f32, width: f32) -> f64 {
        let frac = ((x - left) / width).clamp(0.0, 1.0) as f64;
        self.view_start + frac * (self.view_end - self.view_start)
    }

    fn epoch_to_x(&self, epoch: f64, left: f32, width: f32) -> f32 {
        let frac = (epoch - self.view_start) / (self.view_end - self.view_start);
        left + frac as f32 * width
    }

    fn zoom(&mut self, factor: f64) {
        let center = self.playhead.clamp(self.view_start, self.view_end);
        let half = (self.view_end - self.view_start) * factor / 2.0;
        self.view_start = (center - half).max(self.t_min);
        self.view_end = (center + half).min(self.t_max);
        if self.view_end - self.view_start < 1.0 {
            self.view_end = self.view_start + 1.0;
        }
    }

    /// The render entry point — called by both `eframe::App::ui` and the
    /// visual harness, so the harness drives exactly the real UI.
    pub fn render(&mut self, ctx: &egui::Context) {
        // Keyboard: space toggles play; arrows scrub by ~1% of the visible
        // span per press (so the step naturally adapts to zoom).
        if !ctx.wants_keyboard_input() {
            if ctx.input(|i| i.key_pressed(egui::Key::Space)) {
                self.playing = !self.playing;
            }
            let step = (self.view_end - self.view_start) * 0.01;
            if ctx.input(|i| i.key_pressed(egui::Key::ArrowLeft)) {
                self.playhead = (self.playhead - step).clamp(self.t_min, self.t_max);
                self.playing = false;
            }
            if ctx.input(|i| i.key_pressed(egui::Key::ArrowRight)) {
                self.playhead = (self.playhead + step).clamp(self.t_min, self.t_max);
                self.playing = false;
            }
        }

        let now = Instant::now();
        if self.playing {
            if let Some(prev) = self.last_tick {
                let dt = now.duration_since(prev).as_secs_f64();
                self.playhead += dt * self.speed;
                if self.playhead >= self.view_end {
                    self.playhead = self.view_end;
                    self.playing = false;
                }
            }
            ctx.request_repaint();
        }
        self.last_tick = Some(now);

        self.draw_timeline(ctx);
        self.draw_left_rail(ctx);
        self.draw_right_rail(ctx);
        self.draw_center(ctx);
    }
}

fn lane_label(lane: Lane, ev: &AwEvent) -> (String, String) {
    match lane {
        Lane::Window => (
            ev.field("app").unwrap_or("?").to_string(),
            ev.field("title").unwrap_or("").to_string(),
        ),
        Lane::Web => {
            let url = ev.field("url").unwrap_or("");
            let host = url
                .split("://")
                .nth(1)
                .and_then(|s| s.split('/').next())
                .unwrap_or(url);
            (host.to_string(), ev.field("title").unwrap_or("").to_string())
        }
        Lane::Afk => (ev.field("status").unwrap_or("?").to_string(), String::new()),
        Lane::Workspace => (
            ev.field("workspace").unwrap_or("?").to_string(),
            String::new(),
        ),
    }
}

impl eframe::App for App {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        self.render(ui.ctx());
    }
}

impl App {
    fn draw_timeline(&mut self, ctx: &egui::Context) {
        egui::TopBottomPanel::bottom("timeline")
            .resizable(true)
            .default_height(170.0)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    if ui.button(if self.playing { "⏸" } else { "▶" }).clicked() {
                        self.playing = !self.playing;
                    }
                    ui.label("speed");
                    ui.add(
                        egui::DragValue::new(&mut self.speed)
                            .speed(1.0)
                            .range(1.0..=600.0)
                            .suffix("×"),
                    );
                    if ui.button("＋").on_hover_text("zoom in").clicked() {
                        self.zoom(0.5);
                    }
                    if ui.button("－").on_hover_text("zoom out").clicked() {
                        self.zoom(2.0);
                    }
                    if ui.button("⟲ all").clicked() {
                        self.view_start = self.t_min;
                        self.view_end = self.t_max;
                    }
                    ui.separator();
                    ui.label(RichText::new(fmt_clock(self.playhead)).strong());
                });

                let lanes: [(Lane, &str); 4] = [
                    (Lane::Window, "window"),
                    (Lane::Web, "web"),
                    (Lane::Workspace, "wksp"),
                    (Lane::Afk, "afk"),
                ];
                let row_h = 18.0;
                let label_w = 46.0;
                let avail = ui.available_size();
                let (resp, painter) = ui.allocate_painter(
                    egui::vec2(avail.x, (lanes.len() as f32 + 1.0) * row_h + 8.0),
                    egui::Sense::click_and_drag(),
                );
                let rect = resp.rect;
                let track_left = rect.left() + label_w;
                let track_w = rect.width() - label_w;

                painter.rect_filled(rect, 0.0, Color32::from_rgb(0x1a, 0x1a, 0x1f));

                for (i, (lane, name)) in lanes.iter().enumerate() {
                    let y = rect.top() + 4.0 + i as f32 * row_h;
                    painter.text(
                        egui::pos2(rect.left() + 4.0, y + row_h / 2.0),
                        egui::Align2::LEFT_CENTER,
                        name,
                        egui::FontId::proportional(11.0),
                        Color32::GRAY,
                    );
                    for ev in self.aw.get(*lane) {
                        if ev.end < self.view_start || ev.start > self.view_end {
                            continue;
                        }
                        let x0 = self
                            .epoch_to_x(ev.start.max(self.view_start), track_left, track_w);
                        let x1 = self.epoch_to_x(ev.end.min(self.view_end), track_left, track_w);
                        let (lab, _) = lane_label(*lane, ev);
                        let col = if *lane == Lane::Afk && lab == "afk" {
                            Color32::from_rgb(0x44, 0x44, 0x4a)
                        } else {
                            color_for(&lab)
                        };
                        painter.rect_filled(
                            egui::Rect::from_min_max(
                                egui::pos2(x0, y + 1.0),
                                egui::pos2((x1).max(x0 + 1.0), y + row_h - 1.0),
                            ),
                            0.0,
                            col,
                        );
                    }
                }

                let py = rect.top() + 4.0 + lanes.len() as f32 * row_h;
                painter.text(
                    egui::pos2(rect.left() + 4.0, py + row_h / 2.0),
                    egui::Align2::LEFT_CENTER,
                    "prompts",
                    egui::FontId::proportional(11.0),
                    Color32::GRAY,
                );
                for s in &self.sessions {
                    for p in &s.prompts {
                        if p.epoch < self.view_start || p.epoch > self.view_end {
                            continue;
                        }
                        let x = self.epoch_to_x(p.epoch, track_left, track_w);
                        painter.line_segment(
                            [egui::pos2(x, py + 1.0), egui::pos2(x, py + row_h - 1.0)],
                            egui::Stroke::new(1.5, Color32::from_rgb(0xff, 0xc0, 0x40)),
                        );
                    }
                }

                let px = self.epoch_to_x(self.playhead, track_left, track_w);
                painter.line_segment(
                    [egui::pos2(px, rect.top()), egui::pos2(px, rect.bottom())],
                    egui::Stroke::new(1.5, Color32::WHITE),
                );

                if resp.dragged() || resp.clicked() {
                    if let Some(pos) = resp.interact_pointer_pos() {
                        self.playhead = self.x_to_epoch(pos.x, track_left, track_w);
                        self.playing = false;
                    }
                }
                // Time-axis ticks across the visible span.
                let span = (self.view_end - self.view_start).max(1.0);
                let interval = nice_interval(span / 8.0);
                let mut t = (self.view_start / interval).ceil() * interval;
                while t <= self.view_end {
                    let x = self.epoch_to_x(t, track_left, track_w);
                    painter.line_segment(
                        [
                            egui::pos2(x, rect.bottom() - 14.0),
                            egui::pos2(x, rect.bottom() - 4.0),
                        ],
                        egui::Stroke::new(1.0, Color32::from_rgb(0x55, 0x55, 0x60)),
                    );
                    painter.text(
                        egui::pos2(x, rect.bottom() - 2.0),
                        egui::Align2::CENTER_BOTTOM,
                        fmt_tick(t, interval),
                        egui::FontId::proportional(10.0),
                        Color32::GRAY,
                    );
                    t += interval;
                }

                // Scroll: vertical = zoom centered on pointer, horizontal = pan.
                if resp.hovered() {
                    let scroll = ctx.input(|i| i.smooth_scroll_delta);
                    if scroll.y != 0.0 {
                        if let Some(pos) = resp.hover_pos() {
                            let factor = (1.0 - scroll.y as f64 * 0.005).clamp(0.1, 10.0);
                            let frac =
                                ((pos.x - track_left) / track_w).clamp(0.0, 1.0) as f64;
                            let pointer_epoch =
                                self.view_start + frac * (self.view_end - self.view_start);
                            let max_span = (self.t_max - self.t_min).max(1.0);
                            let new_span = ((self.view_end - self.view_start) * factor)
                                .clamp(1.0, max_span);
                            let mut new_start = pointer_epoch - frac * new_span;
                            let mut new_end = new_start + new_span;
                            if new_start < self.t_min {
                                let s = self.t_min - new_start;
                                new_start += s;
                                new_end += s;
                            }
                            if new_end > self.t_max {
                                let s = new_end - self.t_max;
                                new_start -= s;
                                new_end -= s;
                            }
                            self.view_start = new_start.max(self.t_min);
                            self.view_end = new_end.min(self.t_max);
                        }
                    }
                    if scroll.x != 0.0 && track_w > 0.0 {
                        // Positive scroll.x = swipe right = view shifts to earlier time.
                        let span = self.view_end - self.view_start;
                        let shift = scroll.x as f64 / track_w as f64 * span;
                        let mut new_start = self.view_start - shift;
                        new_start = new_start
                            .max(self.t_min)
                            .min(self.t_max - span);
                        self.view_start = new_start;
                        self.view_end = new_start + span;
                    }
                }
            });
    }

    fn draw_left_rail(&mut self, ctx: &egui::Context) {
        egui::SidePanel::left("agents")
            .resizable(true)
            .default_width(260.0)
            .show(ctx, |ui| {
                ui.heading("Agent sessions");
                ui.separator();
                egui::ScrollArea::vertical().show(ui, |ui| {
                    let mut click: Option<(usize, f64, f64)> = None;
                    for (i, s) in self.sessions.iter().enumerate().rev() {
                        if s.end < self.view_start || s.start > self.view_end {
                            continue;
                        }
                        let selected = self.selection == Selection::Session(i);
                        let proj = s
                            .cwd
                            .as_deref()
                            .and_then(|c| c.rsplit('/').next())
                            .unwrap_or("?");
                        let title = s.title.as_deref().unwrap_or("(untitled)");
                        let text = format!(
                            "{}  ·  {}\n{}  ·  {} prompts",
                            fmt_hm(s.start),
                            proj,
                            title,
                            s.prompts.len()
                        );
                        if ui.selectable_label(selected, text).clicked() {
                            click = Some((i, s.start, s.end));
                        }
                        ui.separator();
                    }
                    if let Some((i, start, end)) = click {
                        self.selection = Selection::Session(i);
                        let pad = (end - start).max(60.0) * 0.05;
                        self.view_start = (start - pad).max(self.t_min);
                        self.view_end = (end + pad).min(self.t_max);
                        self.playhead = start;
                    }
                });
            });
    }

    fn draw_right_rail(&mut self, ctx: &egui::Context) {
        egui::SidePanel::right("terminals")
            .resizable(true)
            .default_width(240.0)
            .show(ctx, |ui| {
                ui.heading("Terminals");
                ui.separator();
                egui::ScrollArea::vertical().show(ui, |ui| {
                    let mut click: Option<usize> = None;
                    for (i, m) in self.metas.iter().enumerate().rev() {
                        if m.end < self.view_start || m.start > self.view_end {
                            continue;
                        }
                        let active = self.playhead >= m.start && self.playhead <= m.end;
                        let selected = self.selection == Selection::Terminal(i);
                        let dot = if active { "●" } else { "○" };
                        let text = format!(
                            "{} {}\n{}–{}",
                            dot,
                            m.label(),
                            fmt_hm(m.start),
                            fmt_hm(m.end)
                        );
                        if ui.selectable_label(selected, text).clicked() {
                            click = Some(i);
                        }
                        ui.separator();
                    }
                    if let Some(i) = click {
                        self.selection = Selection::Terminal(i);
                        let m = &self.metas[i];
                        if self.playhead < m.start || self.playhead > m.end {
                            self.playhead = m.start;
                        }
                    }
                });
            });
    }

    fn draw_center(&mut self, ctx: &egui::Context) {
        egui::CentralPanel::default().show(ctx, |ui| match self.selection {
            Selection::Terminal(idx) => {
                let (start, end) = {
                    let m = &self.metas[idx];
                    (m.start, m.end)
                };
                ui.horizontal(|ui| {
                    ui.heading(self.metas[idx].label());
                    ui.add(
                        egui::Slider::new(&mut self.font_size, 8.0..=22.0)
                            .text("font")
                            .show_value(false),
                    );
                });
                ui.separator();
                if self.playhead < start || self.playhead > end + 1.0 {
                    ui.weak(format!(
                        "(terminal not active at {} — its range is {}–{})",
                        fmt_hm(self.playhead),
                        fmt_hm(start),
                        fmt_hm(end)
                    ));
                    return;
                }
                let playhead = self.playhead;
                let font_size = self.font_size;
                let rec = self.ensure_loaded(idx);
                if let Some(vt) = rec.screen_at_epoch(playhead) {
                    egui::ScrollArea::both().auto_shrink([false, false]).show(
                        ui,
                        |ui| {
                            termview::draw_terminal(ui, &vt, font_size);
                        },
                    );
                }
            }
            Selection::Session(idx) => {
                let mut jump: Option<f64> = None;
                {
                    let s = &self.sessions[idx];
                    ui.heading(s.title.as_deref().unwrap_or("(untitled)"));
                    ui.label(
                        RichText::new(format!(
                            "{}  ·  {}  ·  branch {}",
                            s.cwd.as_deref().unwrap_or("?"),
                            fmt_clock(s.start),
                            s.git_branch.as_deref().unwrap_or("?"),
                        ))
                        .weak(),
                    );
                    ui.separator();
                    egui::ScrollArea::vertical().auto_shrink([false, false]).show(
                        ui,
                        |ui| {
                            for ev in &s.events {
                                let (col, prefix) = match ev.role {
                                    Role::User => {
                                        (Color32::from_rgb(0xff, 0xc0, 0x40), "▶ you")
                                    }
                                    Role::Assistant => {
                                        (Color32::from_rgb(0x90, 0xc0, 0xff), "claude")
                                    }
                                    Role::Tool => (Color32::from_rgb(0x80, 0x90, 0x80), ""),
                                };
                                ui.horizontal_top(|ui| {
                                    if ui
                                        .small_button(fmt_hm(ev.epoch))
                                        .on_hover_text("jump timeline here")
                                        .clicked()
                                    {
                                        jump = Some(ev.epoch);
                                    }
                                    let body = if prefix.is_empty() {
                                        ev.text.clone()
                                    } else {
                                        format!("{prefix}: {}", ev.text)
                                    };
                                    let body: String = body.chars().take(2000).collect();
                                    ui.label(RichText::new(body).color(col));
                                });
                                ui.separator();
                            }
                        },
                    );
                }
                if let Some(t) = jump {
                    self.playhead = t;
                    self.playing = false;
                }
            }
            Selection::None => {
                ui.centered_and_justified(|ui| {
                    ui.weak(
                        "Pick an agent session (left) or a terminal (right). \
                         Drag the timeline to scrub; ▶ to play.",
                    );
                });
            }
        });
    }
}
