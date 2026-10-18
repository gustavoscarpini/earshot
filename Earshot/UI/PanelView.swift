import AppKit
import SwiftUI

/// The menu bar panel.
///
/// Layout with the three sections from the design document, top to bottom:
/// master volume + output device, apps currently playing, and microphone (still
/// a placeholder). The Apps section lists the apps playing audio, with their
/// icon, name, volume slider and mute button.
struct PanelView: View {
    let playingApps: PlayingAppsModel
    let output: OutputModel

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
                Text("Input device, volume and level meter go here.")
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
