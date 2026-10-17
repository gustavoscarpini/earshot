import SwiftUI

/// Earshot's entry point.
///
/// Earshot is a menu bar–only app (`LSUIElement`), so it has no Dock icon and no
/// main window. The only UI is the `MenuBarExtra` panel.
@main
struct EarshotApp: App {
    var body: some Scene {
        MenuBarExtra("Earshot", systemImage: "speaker.wave.2") {
            PanelView()
        }
        .menuBarExtraStyle(.window)
    }
}
