use eframe::egui;

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_inner_size([1500.0, 950.0]),
        ..Default::default()
    };
    eframe::run_native(
        "devlog-player",
        options,
        Box::new(|_cc| Ok(Box::new(devlog_player::app::App::new()))),
    )
}
