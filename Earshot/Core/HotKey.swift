import Foundation

/// A global keyboard shortcut: a virtual key code plus modifiers.
///
/// Pure value type; the Carbon registration lives in `System/`.
struct HotKey: Equatable, Sendable {
    /// Modifier keys, independent of any framework's bit values.
    struct Modifiers: OptionSet, Equatable, Sendable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    /// The ANSI virtual key code (`kVK_ANSI_*`).
    let keyCode: UInt32

    /// The modifiers that must be held.
    let modifiers: Modifiers

    /// The key's label, e.g. `M`.
    let keyLabel: String

    /// The shortcut that toggles the microphone mute: ⌃⌘M.
    static let toggleMicrophoneMute = HotKey(keyCode: 0x2E, modifiers: [.control, .command], keyLabel: "M")

    /// The shortcut as macOS writes it, modifiers in the system order
    /// (⌃⌥⇧⌘), e.g. `⌃⌘M`.
    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + keyLabel
    }
}
