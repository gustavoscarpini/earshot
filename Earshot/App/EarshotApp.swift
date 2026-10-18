import SwiftUI

/// Earshot's entry point.
///
/// Earshot is a menu bar–only app (`LSUIElement`), so it has no Dock icon and no
/// main window. The only UI is the `MenuBarExtra` panel.
@main
struct EarshotApp: App {
    /// The apps-currently-playing model, shared with the panel.
    ///
    /// It is created and started once, at launch, so playing apps are tracked
    /// even before the panel is first opened.
    @State private var playingApps: PlayingAppsModel

    init() {
        let model = PlayingAppsModel(
            monitor: CoreAudioProcessMonitor(),
            tapController: CoreAudioTapController(),
            volumeStore: UserDefaultsVolumeStore()
        )
        _playingApps = State(initialValue: model)
        model.start()
    }

    var body: some Scene {
        MenuBarExtra("Earshot", systemImage: "speaker.wave.2") {
            PanelView(playingApps: playingApps)
        }
        .menuBarExtraStyle(.window)
    }
}
