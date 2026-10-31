import Foundation

/// A system media key press, decoded from an `NSEvent.systemDefined` event.
struct MediaKeyEvent: Equatable, Sendable {
    /// The media keys Earshot cares about (`NX_KEYTYPE_*`).
    enum Key: Int, Sendable {
        case soundUp = 0
        case soundDown = 1
        case mute = 7
    }

    /// The key that was pressed.
    let key: Key

    /// `true` for key-down, `false` for key-up.
    let isDown: Bool

    /// The event subtype of media keys (`NX_SUBTYPE_AUX_CONTROL_BUTTONS`).
    static let systemDefinedSubtype = 8

    /// Decodes a system-defined event, or returns nil when it is not one of
    /// the three keys. `data1` packs the key code in the high 16 bits and the
    /// key state in bits 8–15 (`0xA` is down, `0xB` is up).
    static func decode(subtype: Int, data1: Int) -> MediaKeyEvent? {
        guard subtype == systemDefinedSubtype else { return nil }
        let code = (data1 & 0xFFFF_0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        guard let key = Key(rawValue: code), state == 0xA || state == 0xB else { return nil }
        return MediaKeyEvent(key: key, isDown: state == 0xA)
    }
}

/// What a volume key does to the software master.
enum VolumeKeyAction: Equatable, Sendable {
    /// Move the volume by this signed amount (`-1...1`).
    case step(Float)

    /// Toggle mute.
    case toggleMute

    /// Swallow the event without doing anything (key-up).
    case ignore
}

/// Maps media keys to software master changes, like the system does: a step is
/// 1/16 of the range, or 1/64 with Option+Shift held.
enum VolumeKeyMapper {
    /// The regular step.
    static let coarseStep: Float = 1.0 / 16

    /// The fine step (Option+Shift).
    static let fineStep: Float = 1.0 / 64

    /// The action for `event`. Key-up events map to `.ignore` so a swallowed
    /// key-down never leaves the system a lone key-up.
    static func action(for event: MediaKeyEvent, fine: Bool) -> VolumeKeyAction {
        guard event.isDown else { return .ignore }
        let step = fine ? fineStep : coarseStep
        switch event.key {
        case .soundUp: return .step(step)
        case .soundDown: return .step(-step)
        case .mute: return .toggleMute
        }
    }

    /// `volume + delta`, clamped to `0...1` and snapped to the nearest 1/64 so
    /// repeated steps never accumulate floating point drift.
    static func stepped(_ volume: Float, by delta: Float) -> Float {
        let target = min(max(volume + delta, 0), 1)
        return (target * 64).rounded() / 64
    }
}
