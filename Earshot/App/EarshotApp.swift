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

    /// The output device and master volume model, shared with the panel and
    /// started at launch too, so a software master is applied from the start.
    @State private var output: OutputModel

    init() {
        let model = PlayingAppsModel(
            monitor: CoreAudioProcessMonitor(),
            tapController: CoreAudioTapController(),
            volumeStore: UserDefaultsVolumeStore()
        )
        let outputModel = OutputModel(controller: CoreAudioOutputDeviceController())
        outputModel.onSoftwareMasterChange = { model.setSoftwareMaster($0) }
        _playingApps = State(initialValue: model)
        _output = State(initialValue: outputModel)
        model.start()
        outputModel.start()
    }

    var body: some Scene {
        MenuBarExtra("Earshot", systemImage: "speaker.wave.2") {
            PanelView(playingApps: playingApps, output: output)
        }
        .menuBarExtraStyle(.window)
    }
}
