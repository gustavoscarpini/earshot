import AppKit
import ApplicationServices

/// Intercepts the system volume keys (F11/F12 and mute).
///
/// Needs the Accessibility permission, so it also owns the trust check.
@MainActor
protocol VolumeKeyInterceptor: AnyObject {
    /// Whether Earshot is trusted for Accessibility (no prompt).
    var isTrusted: Bool { get }

    /// Whether the interception is running.
    var isRunning: Bool { get }

    /// Asks macOS to show its Accessibility permission prompt.
    func promptForTrust()

    /// Opens System Settings › Privacy & Security › Accessibility.
    func openAccessibilitySettings()

    /// Starts intercepting. `handler` receives each volume key event together
    /// with whether Option+Shift is held, and returns `true` to consume the
    /// event or `false` to let the system handle it. Returns `false` when the
    /// tap could not be created (no permission).
    func start(handler: @escaping @MainActor (MediaKeyEvent, _ fine: Bool) -> Bool) -> Bool

    /// Stops intercepting. Safe to call when not running.
    func stop()
}

/// `VolumeKeyInterceptor` over a session `CGEventTap` for `systemDefined`
/// events.
///
/// The tap runs on the main run loop, so its callback executes on the main
/// thread and can call the handler synchronously (it must answer whether the
/// event is consumed before returning).
@MainActor
final class CGEventTapVolumeKeys: VolumeKeyInterceptor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate var handler: (@MainActor (MediaKeyEvent, Bool) -> Bool)?

    var isTrusted: Bool { AXIsProcessTrusted() }

    var isRunning: Bool { tap != nil }

    func promptForTrust() {
        // The value of `kAXTrustedCheckOptionPrompt` is a constant string;
        // spelled out because the C global is not concurrency-safe in Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func start(handler: @escaping @MainActor (MediaKeyEvent, Bool) -> Bool) -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.systemDefined.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                // Decode off the actor-isolated state: only Sendable values
                // cross into the main-actor closure.
                let decoded: (subtype: Int, data1: Int, fine: Bool)? = {
                    guard type == .tapDisabledByTimeout || type == .tapDisabledByUserInput || type.rawValue == NSEvent.EventType.systemDefined.rawValue else { return nil }
                    guard let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined else { return nil }
                    let flags = nsEvent.modifierFlags
                    return (Int(nsEvent.subtype.rawValue), nsEvent.data1, flags.contains(.option) && flags.contains(.shift))
                }()
                let isDisabled = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
                let consumed = MainActor.assumeIsolated {
                    let owner = Unmanaged<CGEventTapVolumeKeys>.fromOpaque(refcon).takeUnretainedValue()
                    if isDisabled {
                        owner.reenable()
                        return false
                    }
                    guard let decoded,
                          let media = MediaKeyEvent.decode(subtype: decoded.subtype, data1: decoded.data1),
                          let handler = owner.handler
                    else { return false }
                    return handler(media, decoded.fine)
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        self.handler = handler
        return true
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
        handler = nil
    }

    /// Turns the tap back on after macOS disabled it (timeout or user input).
    fileprivate func reenable() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}
