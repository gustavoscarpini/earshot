import AppKit
import Observation

/// The menu bar icon: follows the output, input and playing apps models and
/// publishes the image to show (DESIGN §4).
///
/// It re-resolves the glyph whenever an observed property changes and only
/// redraws when the glyph actually changes.
@MainActor
@Observable
final class MenuBarIconModel {
    /// The image for the `MenuBarExtra` label.
    private(set) var image: NSImage

    /// The glyph currently shown.
    private(set) var glyph: MenuBarGlyph

    @ObservationIgnored private let output: OutputModel
    @ObservationIgnored private let input: InputModel
    @ObservationIgnored private let playingApps: PlayingAppsModel
    @ObservationIgnored private var isStarted = false

    init(output: OutputModel, input: InputModel, playingApps: PlayingAppsModel) {
        self.output = output
        self.input = input
        self.playingApps = playingApps
        let glyph = MenuBarGlyph.resolve(.init())
        self.glyph = glyph
        self.image = MenuBarIconRenderer.image(for: glyph)
    }

    /// Starts following the models. Call once, at launch.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        track()
    }

    /// Resolves the glyph and re-arms observation of the properties it read.
    private func track() {
        let newGlyph = withObservationTracking {
            MenuBarGlyph.resolve(currentInputs())
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.track() }
        }
        guard newGlyph != glyph else { return }
        glyph = newGlyph
        image = MenuBarIconRenderer.image(for: newGlyph)
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
