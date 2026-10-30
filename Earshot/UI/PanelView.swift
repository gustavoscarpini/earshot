import AppKit
import SwiftUI

/// The menu bar panel.
///
/// Layout with the three sections from the design document, top to bottom:
/// master volume + output device, apps currently playing, and microphone. The
/// Apps section lists the apps playing audio, with their icon, name, volume
/// slider and mute button.
struct PanelView: View {
    let playingApps: PlayingAppsModel
    let output: OutputModel
    let input: InputModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Earshot")
                .font(.headline)

            PanelSection(title: "Output") {
                OutputSection(model: output)
            }

            PanelSection(title: "Apps") {
                appsSection
            }

            PanelSection(title: "Microphone") {
                InputSection(model: input)
            }

            Divider()

            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder private var appsSection: some View {
        if playingApps.apps.isEmpty {
            Text("No apps are playing audio.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(playingApps.apps) { app in
                    PlayingAppRow(app: app, model: playingApps)
                }
            }
        }
    }
}

/// One row in the Apps section: icon, name, volume slider and mute button.
private struct PlayingAppRow: View {
    let app: PlayingApp
    let model: PlayingAppsModel

    var body: some View {
        let muted = model.isMuted(app.id)
        let volume = model.volume(for: app.id)

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                icon
                    .frame(width: 16, height: 16)
                Text(app.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(volume, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button {
                    model.toggleMute(app.id)
                } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.borderless)
                .help(muted ? "Unmute" : "Mute")
            }
            Slider(
                value: Binding(
                    get: { Double(model.volume(for: app.id)) },
                    set: { model.setVolume(Float($0), for: app.id) }
                ),
                in: 0...1
            )
            .controlSize(.small)
            .disabled(muted)
        }
        .opacity(app.isPlaying ? 1 : 0.4)
        .help(app.name)
    }

    @ViewBuilder private var icon: some View {
        if app.id.hasSuffix(".app") {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.id))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }
}

/// The Output section: device picker, mute button, master slider and percent.
private struct OutputSection: View {
    let model: OutputModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(
                "Output",
                selection: Binding(
                    get: { model.selectedUID },
                    set: { uid in
                        if let uid { model.select(uid: uid) }
                    }
                )
            ) {
                ForEach(model.devices) { device in
                    Text(device.name).tag(Optional(device.uid))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            HStack(spacing: 8) {
                Button {
                    model.toggleMute()
                } label: {
                    Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.borderless)
                .help(model.isMuted ? "Unmute" : "Mute")

                Slider(
                    value: Binding(
                        get: { Double(model.volume) },
                        set: { model.setVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .disabled(model.isMuted)

                Text(model.volume, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if model.usesSoftwareMaster {
                Text("Software volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The Microphone section: device picker, mute button, input slider and percent,
/// plus the opt-in level meter.
private struct InputSection: View {
    let model: InputModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(
                "Microphone",
                selection: Binding(
                    get: { model.selectedUID },
                    set: { uid in
                        if let uid { model.select(uid: uid) }
                    }
                )
            ) {
                ForEach(model.devices) { device in
                    Text(device.name).tag(Optional(device.uid))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            HStack(spacing: 8) {
                Button {
                    model.toggleMute()
                } label: {
                    Image(systemName: model.isMuted ? "mic.slash.fill" : "mic.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.borderless)
                .disabled(!model.canMute)
                .help(model.canMute ? (model.isMuted ? "Unmute" : "Mute") : "Not supported by this device")

                Slider(
                    value: Binding(
                        get: { Double(model.volume) },
                        set: { model.setVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .disabled(model.isMuted || !model.hasHardwareVolume)

                Text(model.volume, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if !model.hasHardwareVolume {
                Text("Not supported by this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(
                "Monitor level",
                isOn: Binding(
                    get: { model.isMonitoring },
                    set: { model.setMonitoring($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.mini)

            if model.isMonitoring {
                LevelBar(level: model.level)
            }

            if model.meterError {
                Text("Microphone access denied")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // The meter captures the microphone, so it only runs while the panel is
        // visible.
        .onDisappear {
            model.setMonitoring(false)
        }
    }
}

/// A thin horizontal bar filled to `level` (`0...1`).
private struct LevelBar: View {
    let level: Float

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * CGFloat(min(max(level, 0), 1)))
                }
            }
            .clipShape(Capsule())
    }
}

/// A titled group used by the panel sections.
private struct PanelSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content
        }
    }
}
