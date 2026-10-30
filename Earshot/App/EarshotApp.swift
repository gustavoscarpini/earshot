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

    /// The now playing model, shared with the panel and started at launch. It
    /// stops its adapter process when the app terminates.
    @State private var nowPlaying: NowPlayingModel

    /// The menu bar icon, derived from the output, input and playing apps
    /// models (DESIGN §4).
    @State private var menuBarIcon: MenuBarIconModel

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
        let nowPlayingModel = NowPlayingModel(source: MediaRemoteAdapterSource())
        _output = State(initialValue: outputModel)
        _input = State(initialValue: inputModel)
        _nowPlaying = State(initialValue: nowPlayingModel)
        let iconModel = MenuBarIconModel(output: outputModel, input: inputModel, playingApps: model)
        _menuBarIcon = State(initialValue: iconModel)
        model.start()
        outputModel.start()
        inputModel.start()
        iconModel.start()
        // The unit tests run inside the app as their host, which is killed
        // without a graceful quit; it must not spawn the adapter's perl process.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            nowPlayingModel.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(nowPlaying: nowPlaying, playingApps: playingApps, output: output, input: input)
        } label: {
            Label {
                Text("Earshot")
            } icon: {
                Image(nsImage: menuBarIcon.image)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
