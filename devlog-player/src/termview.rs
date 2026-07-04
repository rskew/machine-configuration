//! Renders an `avt::Vt` screen into an egui painter: one background rect + one
//! glyph per cell, with ANSI/256/RGB colors, bold/faint/inverse/underline, and
//! the cursor. This is the work a TUI host would have done for free.

use avt::{Color as AvtColor, Vt};
use eframe::egui::{self, Align2, Color32, FontId, Pos2, Rect, Sense, Stroke, Vec2};

pub const BG: Color32 = Color32::from_rgb(0x12, 0x12, 0x16);
pub const FG: Color32 = Color32::from_rgb(0xcc, 0xcc, 0xcc);

const ANSI16: [(u8, u8, u8); 16] = [
    (0x00, 0x00, 0x00),
    (0xcd, 0x32, 0x32),
    (0x2e, 0xa8, 0x43),
    (0xc7, 0xa6, 0x16),
    (0x3b, 0x6e, 0xd9),
    (0xa0, 0x4a, 0xc4),
    (0x2c, 0xa6, 0xb5),
    (0xd0, 0xd0, 0xd0),
    (0x55, 0x55, 0x55),
    (0xff, 0x5f, 0x5f),
    (0x5f, 0xd7, 0x5f),
    (0xff, 0xd7, 0x5f),
    (0x5f, 0x9f, 0xff),
    (0xd7, 0x5f, 0xd7),
    (0x5f, 0xd7, 0xd7),
    (0xff, 0xff, 0xff),
];

fn palette(i: u8) -> (u8, u8, u8) {
    match i {
        0..=15 => ANSI16[i as usize],
        16..=231 => {
            let i = i - 16;
            let cube = |v: u8| if v == 0 { 0 } else { 55 + v * 40 };
            (cube(i / 36), cube((i % 36) / 6), cube(i % 6))
        }
        232..=255 => {
            let v = 8 + (i - 232) * 10;
            (v, v, v)
        }
    }
}

fn to_color(c: AvtColor) -> Color32 {
    match c {
        AvtColor::RGB(rgb) => Color32::from_rgb(rgb.r, rgb.g, rgb.b),
        AvtColor::Indexed(i) => {
            let (r, g, b) = palette(i);
            Color32::from_rgb(r, g, b)
        }
    }
}

/// Cell size for a given monospace font, so callers can size containers.
pub fn cell_size(ui: &egui::Ui, font_size: f32) -> (f32, f32) {
    let font = FontId::monospace(font_size);
    ui.ctx()
        .fonts_mut(|f| (f.glyph_width(&font, 'M'), f.row_height(&font)))
}

pub fn draw_terminal(ui: &mut egui::Ui, vt: &Vt, font_size: f32) {
    let font = FontId::monospace(font_size);
    let (cw, ch) = cell_size(ui, font_size);
    let (cols, rows) = vt.size();
    let size = Vec2::new(cw * cols as f32, ch * rows as f32);
    let (resp, painter) = ui.allocate_painter(size, Sense::hover());
    let origin = resp.rect.min;

    painter.rect_filled(resp.rect, 0.0, BG);

    for (r, line) in vt.view().enumerate() {
        for (col, cell) in line.cells().iter().enumerate() {
            let span = cell.width();
            if span == 0 {
                continue; // trailing half of a wide glyph
            }
            let pen = cell.pen();
            let mut fg = pen.foreground().map(to_color).unwrap_or(FG);
            let mut bg = pen.background().map(to_color);
            if pen.is_inverse() {
                let prev_fg = fg;
                fg = bg.unwrap_or(BG);
                bg = Some(prev_fg);
            }
            if pen.is_faint() {
                fg = fg.gamma_multiply(0.6);
            }

            let cell_w = cw * span as f32;
            let x = origin.x + cw * col as f32;
            let y = origin.y + ch * r as f32;
            let rect = Rect::from_min_size(Pos2::new(x, y), Vec2::new(cell_w, ch));

            if let Some(b) = bg {
                painter.rect_filled(rect, 0.0, b);
            }
            let chr = cell.char();
            if chr != ' ' {
                painter.text(Pos2::new(x, y), Align2::LEFT_TOP, chr, font.clone(), fg);
            }
            if pen.is_underline() {
                let yb = y + ch - 1.0;
                painter.line_segment(
                    [Pos2::new(x, yb), Pos2::new(x + cell_w, yb)],
                    Stroke::new(1.0, fg),
                );
            }
        }
    }

    let cursor = vt.cursor();
    if cursor.visible {
        let x = origin.x + cw * cursor.col as f32;
        let y = origin.y + ch * cursor.row as f32;
        painter.rect_filled(
            Rect::from_min_size(Pos2::new(x, y), Vec2::new(cw, ch)),
            0.0,
            Color32::from_rgba_unmultiplied(0xcc, 0xcc, 0xcc, 0x70),
        );
    }
}
