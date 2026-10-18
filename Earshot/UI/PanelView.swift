import AppKit
import SwiftUI

/// The menu bar panel.
///
/// Placeholder layout with the three sections from the design document, top to
/// bottom: master volume + output device, apps currently playing, and
/// microphone. The Apps section lists the apps playing audio, with their icon
/// and name; volume control is wired up in later steps.
struct PanelView: View {
    let playingApps: PlayingAppsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Earshot")
                .font(.headline)

            PanelSection(title: "Output") {
                Text("Master volume and output device controls go here.")
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
