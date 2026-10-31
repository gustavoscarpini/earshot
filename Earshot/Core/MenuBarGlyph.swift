import Foundation

/// The main glyph of the menu bar icon (DESIGN §4).
///
/// Pure value type: `resolve` turns a snapshot of the audio state into a glyph,
/// so the priority rules are unit-testable without AppKit or Core Audio. The
/// microphone never affects the glyph; a muted microphone is a separate badge
/// (`MenuBarIcon`). The drawing lives in `MenuBarIconRenderer`.
enum MenuBarGlyph: Equatable, Sendable {
    /// The output is muted: `speaker.slash.fill`.
    case outputMuted

    /// At least one app is playing audio: a still four-bar equalizer.
    case playing

    /// Idle on an external output (headphones, AirPods, a display, ...): the
    /// device's own symbol.
    case device(symbol: String)

    /// Idle on the built-in speakers: a speaker whose waves follow the volume.
    case speaker(volume: Double)

    /// The audio state the icon is derived from.
    struct Inputs: Equatable, Sendable {
        var isMicMuted = false
        var isOutputMuted = false
        var isPlaying = false
        var outputVolume: Double = 1
        var outputDevice: AudioDevice?
    }

    /// Picks the glyph, most important state first: a muted output, playback,
    /// then the idle output device. `isMicMuted` is ignored here.
    static func resolve(_ inputs: Inputs) -> MenuBarGlyph {
        if inputs.isOutputMuted { return .outputMuted }
        if inputs.isPlaying { return .playing }
        if let device = inputs.outputDevice, device.transport != .builtIn {
            return .device(symbol: device.symbolName(for: .output))
        }
        return .speaker(volume: min(max(inputs.outputVolume, 0), 1))
    }
}

/// The whole menu bar icon: the output glyph plus, while the microphone is
/// muted, a small `mic.slash.fill` badge drawn to its right (DESIGN §4, §6).
struct MenuBarIcon: Equatable, Sendable {
    /// The output glyph, resolved as if the microphone did not exist.
    var glyph: MenuBarGlyph

    /// Whether the muted-microphone badge is shown.
    var isMicMuted: Bool

    /// Resolves the glyph and the badge from the audio state.
    static func resolve(_ inputs: MenuBarGlyph.Inputs) -> MenuBarIcon {
        MenuBarIcon(glyph: MenuBarGlyph.resolve(inputs), isMicMuted: inputs.isMicMuted)
    }
}

/// The bar heights of the playing glyph, each in `0...1`: uneven so it reads
/// as an equalizer at a glance, and still, so the menu bar stays calm.
enum EqualizerLevels {
    static let bars: [Double] = [0.35, 0.7, 0.45, 0.85]
}
