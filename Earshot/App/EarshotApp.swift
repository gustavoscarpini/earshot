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

    /// The microphone model, shared with the panel and started at launch so the
    /// menu bar icon reflects a muted microphone. The level meter stays off until
    /// the user turns it on.
    @State private var input: InputModel

    init() {
        let model = PlayingAppsModel(
            monitor: CoreAudioProcessMonitor(),
            tapController: CoreAudioTapController(),
            volumeStore: UserDefaultsVolumeStore()
        )
        let outputModel = OutputModel(controller: CoreAudioDeviceController(direction: .output))
        outputModel.onSoftwareMasterChange = { model.setSoftwareMaster($0) }
        _playingApps = State(initialValue: model)
        let inputModel = InputModel(
            controller: CoreAudioDeviceController(direction: .input),
            meter: AVAudioEngineLevelMeter()
        )
        _output = State(initialValue: outputModel)
        _input = State(initialValue: inputModel)
        model.start()
        outputModel.start()
        inputModel.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(playingApps: playingApps, output: output, input: input)
        } label: {
            Label("Earshot", systemImage: input.isMuted ? "mic.slash.fill" : "speaker.wave.2")
        }
        .menuBarExtraStyle(.window)
    }
}
