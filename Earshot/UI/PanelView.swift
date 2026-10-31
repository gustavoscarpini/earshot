import AppKit
import SwiftUI

/// The menu bar panel.
///
/// From top to bottom: the now playing header (or its empty state), then the
/// Output, Apps and Microphone sections separated by thin dividers, and a footer
/// with the Sound Settings shortcut, the settings menu and Quit. The Apps section lists the apps
/// playing audio, with their icon, name, volume slider and mute button.
struct PanelView: View {
    let nowPlaying: NowPlayingModel
    let playingApps: PlayingAppsModel
    let output: OutputModel
    let input: InputModel
    let settings: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            if nowPlaying.info != nil {
                NowPlayingHeader(model: nowPlaying)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    PanelTitle()
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                    EmptyNowPlaying()
                }
            }

            PanelSection(
                icon: "speaker.wave.2.fill",
                title: "Output",
                trailing: output.isMuted ? Text("Muted") : Text(output.volume, format: .percent.precision(.fractionLength(0)))
            ) {
                OutputSection(model: output)
            }

            PanelSection(
                icon: "square.grid.2x2.fill",
                title: "Playing now",
                trailing: Text(playingApps.apps.count, format: .number)
            ) {
                appsSection
            }

            PanelSection(icon: "mic.fill", title: "Microphone", trailing: inputTrailing) {
                InputSection(model: input, micUsers: playingApps.micUsers)
            }

            Divider().opacity(0.5)

            HStack {
                Button {
                    openSoundSettings()
                } label: {
                    Label("Sound Settings…", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                SettingsMenu(model: settings)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
                .keyboardShortcut("q")
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 340)
        .background(.regularMaterial)
        // The input meter captures the microphone, so it may only run while the
        // panel is visible (DESIGN §2).
        .onAppear {
            input.panelDidAppear()
            playingApps.panelDidAppear()
            settings.panelDidAppear()
        }
        .onDisappear {
            input.panelDidDisappear()
            playingApps.panelDidDisappear()
        }
        .onChange(of: playingApps.micUsers, initial: true) { _, users in
            input.setOtherAppsUsingMic(!users.isEmpty)
        }
    }

    /// The microphone volume, "Muted", or nothing when the device has no
    /// hardware volume to show.
    private var inputTrailing: Text? {
        if input.isMuted { return Text("Muted") }
        guard input.hasHardwareVolume else { return nil }
        return Text(input.volume, format: .percent.precision(.fractionLength(0)))
    }

    @ViewBuilder private var appsSection: some View {
        if playingApps.apps.isEmpty {
            Text("No apps are playing audio.")
                .foregroundStyle(.secondary)
        } else {
            AppsList(model: playingApps)
        }
    }

    private func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The rows of the Apps section. A separate view so the ~25 Hz meter updates
/// re-render only the rows, not the whole panel.
private struct AppsList: View {
    let model: PlayingAppsModel

    var body: some View {
        VStack(spacing: 10) {
            ForEach(model.apps) { app in
                AppMixerRow(app: app, model: model, level: model.level(for: app.id))
            }
        }
    }
}

/// The Output section: device cards, then the mute button and master slider.
private struct OutputSection: View {
    let model: OutputModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DeviceList(
                devices: model.devices,
                selectedUID: model.selectedUID,
                direction: .output,
                subtitle: { device, _ in Text(LocalizedStringKey(device.subtitleKey)) },
                select: { model.select(uid: $0) }
            )

            IconSlider(
                value: Binding(
                    get: { Double(model.volume) },
                    set: { model.setVolume(Float($0)) }
                ),
                minIcon: model.isMuted ? "speaker.slash.fill" : "speaker.fill",
                maxIcon: "speaker.wave.3.fill",
                isSliderDisabled: model.isMuted,
                onMinIconTap: { model.toggleMute() },
                minIconHelp: model.isMuted ? "Unmute" : "Mute"
            )
            .padding(.top, 4)

            if model.usesSoftwareMaster {
                Text("Software volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The Microphone section: device cards, the mute button and input slider, and
/// the level meter.
///
/// The meter runs by itself while another app uses the microphone; otherwise a
/// small button starts and stops it (see `InputModel`).
private struct InputSection: View {
    let model: InputModel

    /// The names of the other apps capturing the microphone.
    let micUsers: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DeviceList(
                devices: model.devices,
                selectedUID: model.selectedUID,
                direction: .input,
                subtitle: { device, isSelected in
                    isSelected && !micUsers.isEmpty
                        ? Text(verbatim: Self.inUseText(micUsers))
                        : Text(LocalizedStringKey(device.subtitleKey))
                },
                showsInUseDot: { _, isSelected in isSelected && !micUsers.isEmpty },
                select: { model.select(uid: $0) }
            )

            IconSlider(
                value: Binding(
                    get: { Double(model.volume) },
                    set: { model.setVolume(Float($0)) }
                ),
                minIcon: model.isMuted ? "mic.slash.fill" : "mic",
                maxIcon: "mic.fill",
                isSliderDisabled: model.isMuted || !model.hasHardwareVolume,
                isMinIconEnabled: model.canMute,
                onMinIconTap: { model.toggleMute() },
                minIconHelp: model.canMute
                    ? (model.isMuted ? "Unmute (\(HotKey.toggleMicrophoneMute.display))" : "Mute (\(HotKey.toggleMicrophoneMute.display))")
                    : "Not supported by this device"
            )
            .padding(.top, 4)

            if !model.hasHardwareVolume {
                Text("Not supported by this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.isMonitoring || !model.otherAppsUsingMic {
                HStack(spacing: 8) {
                    if model.isMonitoring {
                        LevelMeter(level: model.level, segments: 16)
                            .frame(height: 6)
                    } else {
                        Spacer(minLength: 0)
                    }
                    if !model.otherAppsUsingMic {
                        Button {
                            model.toggleManualMonitoring()
                        } label: {
                            Image(systemName: "waveform")
                                .foregroundStyle(model.isMonitoring ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(model.isMonitoring ? "Hide input level" : "Show input level")
                        .accessibilityLabel(model.isMonitoring ? "Hide input level" : "Show input level")
                    }
                }
            }

            if model.meterError {
                Text("Microphone access denied")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "In use by Zoom", or "In use by Zoom and 2 more" for several apps.
    private static func inUseText(_ names: [String]) -> String {
        guard let first = names.first else { return "" }
        if names.count > 1 {
            return String(localized: "In use by \(first) and \(names.count - 1) more")
        }
        return String(localized: "In use by \(first)")
    }
}

/// A slider with an icon at each end. The left icon can act as a button (the
/// mute toggle).
private struct IconSlider: View {
    @Binding var value: Double
    let minIcon: String
    let maxIcon: String
    var isSliderDisabled = false
    var isMinIconEnabled = true
    let onMinIconTap: () -> Void
    let minIconHelp: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onMinIconTap) {
                Image(systemName: minIcon)
                    .foregroundStyle(minIcon.contains("slash") ? Color.red : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .disabled(!isMinIconEnabled)
            .help(minIconHelp)
            .accessibilityLabel(minIconHelp)

            Slider(value: $value, in: 0...1)
                .controlSize(.small)
                .disabled(isSliderDisabled)

            Image(systemName: maxIcon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
        }
        .font(.caption)
    }
}

/// A titled group used by the panel sections: an icon, a title and an optional
/// trailing value, above the content, with a thin divider on top.
private struct PanelSection<Content: View>: View {
    let icon: String
    let title: LocalizedStringKey
    var trailing: Text?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                Spacer()
                if let trailing {
                    trailing.monospacedDigit()
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Divider().opacity(0.5)
        }
    }
}

/// The gear menu in the footer: launch at login, volume keys and the
/// microphone shortcut (DESIGN §15–§17).
private struct SettingsMenu: View {
    let model: SettingsModel

    var body: some View {
        Menu {
            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchAtLogin != .disabled },
                set: { model.setLaunchAtLogin($0) }
            ))
            if model.launchAtLogin == .requiresApproval {
                Button("Allow in Login Items settings…") {
                    model.openLoginItemsSettings()
                }
            }

            Toggle("Use volume keys for outputs without hardware volume", isOn: Binding(
                get: { model.volumeKeysEnabled },
                set: { model.setVolumeKeysEnabled($0) }
            ))
            if model.volumeKeysEnabled, !model.isAccessibilityTrusted {
                Button("Allow in Accessibility settings…") {
                    model.openAccessibilitySettings()
                }
            }

            Divider()

            // The global hot key catches ⌃⌘M first; the shortcut here only
            // shows it next to the item, the way menus do.
            Button(model.isMicrophoneMuted ? "Unmute Microphone" : "Mute Microphone") {
                model.toggleMicrophoneMute()
            }
            .keyboardShortcut("m", modifiers: [.control, .command])
            .disabled(!model.canMuteMicrophone)
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Settings")
        .accessibilityLabel("Settings")
    }
}
