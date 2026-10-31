import AppKit
import Observation

/// The menu bar icon: follows the output, input and playing apps models and
/// publishes the image to show (DESIGN §4).
///
/// It re-resolves the icon (output glyph plus the muted microphone badge)
/// whenever an observed property changes and only redraws when the icon
/// actually changes.
@MainActor
@Observable
final class MenuBarIconModel {
    /// The image for the `MenuBarExtra` label.
    private(set) var image: NSImage

    /// The icon currently shown.
    private(set) var icon: MenuBarIcon

    @ObservationIgnored private let output: OutputModel
    @ObservationIgnored private let input: InputModel
    @ObservationIgnored private let playingApps: PlayingAppsModel
    @ObservationIgnored private var isStarted = false

    init(output: OutputModel, input: InputModel, playingApps: PlayingAppsModel) {
        self.output = output
        self.input = input
        self.playingApps = playingApps
        let icon = MenuBarIcon.resolve(.init())
        self.icon = icon
        self.image = MenuBarIconRenderer.image(for: icon)
    }

    /// Starts following the models. Call once, at launch.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        track()
    }

    /// Resolves the icon and re-arms observation of the properties it read.
    private func track() {
        let newIcon = withObservationTracking {
            MenuBarIcon.resolve(currentInputs())
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.track() }
        }
        guard newIcon != icon else { return }
        icon = newIcon
        image = MenuBarIconRenderer.image(for: newIcon)
    }

    private func currentInputs() -> MenuBarGlyph.Inputs {
        MenuBarGlyph.Inputs(
            isMicMuted: input.isMuted,
            isOutputMuted: output.isMuted,
            isPlaying: playingApps.apps.contains(where: \.isPlaying),
            outputVolume: Double(output.volume),
            outputDevice: output.devices.first { $0.uid == output.selectedUID }
        )
    }
}
