import Carbon.HIToolbox
import Foundation

/// Registers system-wide keyboard shortcuts.
@MainActor
protocol GlobalHotKeys: AnyObject {
    /// Registers `hotKey`; `handler` runs on the main actor each time it is
    /// pressed. Returns `false` when the system refuses (e.g. another app owns
    /// the combination). Registering the same hot key again replaces nothing:
    /// call `unregisterAll()` first.
    func register(_ hotKey: HotKey, handler: @escaping @MainActor () -> Void) -> Bool

    /// Removes every registered shortcut.
    func unregisterAll()
}

/// `GlobalHotKeys` over Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility permission.
@MainActor
final class CarbonGlobalHotKeys: GlobalHotKeys {
    /// The four-character signature of Earshot's hot key IDs ("ERSH").
    private static let signature: OSType = 0x4552_5348

    /// The handlers of the live instance, by hot key ID. Read only on the main
    /// actor, from `dispatch`.
    private static var handlers: [UInt32: @MainActor () -> Void] = [:]

    /// Set once the application event handler is installed.
    private static var isHandlerInstalled = false

    private var references: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1

    func register(_ hotKey: HotKey, handler: @escaping @MainActor () -> Void) -> Bool {
        Self.installHandlerIfNeeded()
        let id = nextID
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            Self.carbonModifiers(hotKey.modifiers),
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        nextID += 1
        references.append(reference)
        Self.handlers[id] = handler
        return true
    }

    func unregisterAll() {
        for reference in references {
            UnregisterEventHotKey(reference)
        }
        for id in 1..<nextID {
            Self.handlers[id] = nil
        }
        references.removeAll()
    }

    // MARK: Private

    private static func carbonModifiers(_ modifiers: HotKey.Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    /// Installs the process-wide `kEventHotKeyPressed` handler once.
    ///
    /// The C callback carries no Swift context: it extracts the hot key ID
    /// (a `UInt32`) and hops to the main queue, as the audio and I/O threads do
    /// elsewhere (AGENTS.md), before touching the handlers.
    private static func installHandlerIfNeeded() {
        guard !isHandlerInstalled else { return }
        isHandlerInstalled = true
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == CarbonGlobalHotKeys.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        CarbonGlobalHotKeys.handlers[id]?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }
}
