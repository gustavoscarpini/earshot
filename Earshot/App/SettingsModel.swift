import AppKit
import Foundation
import Observation

/// Owns the options of the settings menu and the system integrations behind
/// them (DESIGN §15–§17): the global mic-mute shortcut, the volume keys for
/// outputs without hardware volume, and launch at login.
///
/// - The mic-mute shortcut is always on once `start()` ran.
/// - The volume keys are opt-in (`volumeKeysEnabled`, persisted). The event tap
///   runs only while the option is on, Accessibility is trusted, and it is
///   re-checked whenever the panel opens (`panelDidAppear()`), which is how a
///   permission granted in System Settings is picked up without polling.
/// - Launch at login is never stored: `launchAtLogin` is read from the system.
@MainActor
@Observable
final class SettingsModel {
    /// UserDefaults key of the volume keys option.
    static let volumeKeysKey = "useVolumeKeysForSoftwareMaster"

    /// The system's launch at login status.
    private(set) var launchAtLogin: LaunchAtLoginStatus = .disabled

    /// Whether the volume keys option is on.
    private(set) var volumeKeysEnabled: Bool

    /// Whether Earshot is trusted for Accessibility.
    private(set) var isAccessibilityTrusted = false

    /// Whether the volume key event tap is running.
    private(set) var isVolumeKeyTapRunning = false

    /// Whether the mic-mute shortcut was registered (it fails when another app
    /// owns ⌃⌘M).
    private(set) var isMicShortcutRegistered = false

    private let launchService: any LaunchAtLoginService
    private let volumeKeys: any VolumeKeyInterceptor
    private let hotKeys: any GlobalHotKeys
    private let input: InputModel
    private let output: OutputModel
    private let defaults: UserDefaults
    private let beep: @MainActor () -> Void
    private var isStarted = false

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - launchService: Reads and changes the login item.
    ///   - volumeKeys: The media key event tap and Accessibility trust.
    ///   - hotKeys: Registers the mic-mute shortcut.
    ///   - input: The microphone, muted by the shortcut.
    ///   - output: The output whose software master the volume keys drive.
    ///   - defaults: Where the volume keys option is stored.
    ///   - beep: Feedback when the microphone cannot be muted.
    init(
        launchService: any LaunchAtLoginService,
        volumeKeys: any VolumeKeyInterceptor,
        hotKeys: any GlobalHotKeys,
        input: InputModel,
        output: OutputModel,
        defaults: UserDefaults = .standard,
        beep: @escaping @MainActor () -> Void = { NSSound.beep() }
    ) {
        self.launchService = launchService
        self.volumeKeys = volumeKeys
        self.hotKeys = hotKeys
        self.input = input
        self.output = output
        self.defaults = defaults
        self.beep = beep
        volumeKeysEnabled = defaults.bool(forKey: Self.volumeKeysKey)
    }

    /// Registers the shortcut, reads the system state and starts the volume
    /// key tap when it is enabled and allowed. Idempotent.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        isMicShortcutRegistered = hotKeys.register(.toggleMicrophoneMute) { [weak self] in
            self?.toggleMicrophoneMute()
        }
        refresh()
    }

    /// Unregisters the shortcut and stops the tap. Idempotent.
    func stop() {
        guard isStarted else { return }
        isStarted = false
        hotKeys.unregisterAll()
        isMicShortcutRegistered = false
        volumeKeys.stop()
        isVolumeKeyTapRunning = false
    }

    /// The panel opened: re-read the system state, so a launch at login change
    /// or an Accessibility grant made elsewhere shows up, and retry the tap.
    func panelDidAppear() {
        refresh()
    }

    /// Registers or unregisters the login item, then re-reads the real status.
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try launchService.register()
            } else {
                try launchService.unregister()
            }
        } catch {
            // The status below tells the truth if it did not work.
        }
        refresh()
    }

    /// Opens Login Items settings, where a pending approval is given.
    func openLoginItemsSettings() {
        launchService.openLoginItemsSettings()
    }

    /// Turns the volume keys option on or off. Turning it on without
    /// Accessibility trust shows the system prompt.
    func setVolumeKeysEnabled(_ on: Bool) {
        volumeKeysEnabled = on
        defaults.set(on, forKey: Self.volumeKeysKey)
        if on, !volumeKeys.isTrusted {
            volumeKeys.promptForTrust()
        }
        refresh()
    }

    /// Opens Accessibility settings, where the permission is given.
    func openAccessibilitySettings() {
        volumeKeys.openAccessibilitySettings()
    }

    /// Whether the microphone is muted, for the menu item's title.
    var isMicrophoneMuted: Bool { input.isMuted }

    /// Whether the microphone can be muted, which enables the menu item.
    var canMuteMicrophone: Bool { input.canMute }

    /// The mic-mute shortcut and menu item action: toggles the mute, or beeps
    /// when the microphone cannot be muted.
    func toggleMicrophoneMute() {
        guard input.canMute else {
            beep()
            return
        }
        input.toggleMute()
    }

    /// Handles a media key from the event tap and returns whether to consume
    /// it. Only consumed while the output uses the software master.
    func handleMediaKey(_ event: MediaKeyEvent, fine: Bool) -> Bool {
        guard output.usesSoftwareMaster else { return false }
        switch VolumeKeyMapper.action(for: event, fine: fine) {
        case .ignore:
            break
        case .toggleMute:
            output.toggleMute()
        case .step(let delta):
            // Like the system, changing the volume unmutes.
            if output.isMuted { output.toggleMute() }
            output.setVolume(VolumeKeyMapper.stepped(output.volume, by: delta))
        }
        return true
    }

    // MARK: Private

    /// Re-reads the login item and trust, and starts or stops the tap to match.
    private func refresh() {
        launchAtLogin = launchService.status
        isAccessibilityTrusted = volumeKeys.isTrusted
        guard isStarted else { return }
        let wanted = volumeKeysEnabled && isAccessibilityTrusted
        if wanted, !volumeKeys.isRunning {
            _ = volumeKeys.start { [weak self] event, fine in
                self?.handleMediaKey(event, fine: fine) ?? false
            }
        } else if !wanted, volumeKeys.isRunning {
            volumeKeys.stop()
        }
        isVolumeKeyTapRunning = volumeKeys.isRunning
    }
}
