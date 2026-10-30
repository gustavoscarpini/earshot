import AppKit
import SwiftUI

/// One row in the Apps section: icon, name, percent (or "Muted"), a small
/// volume slider, an optional level meter and the mute button.
struct AppMixerRow: View {
    let app: PlayingApp
    let model: PlayingAppsModel

    /// The app's output level, `0...1`. The meter under the slider shows only
    /// when this is non-nil.
    var level: Float?

    var body: some View {
        let muted = model.isMuted(app.id)
        let volume = model.volume(for: app.id)
        let muteLabel: LocalizedStringKey = muted ? "Unmute" : "Mute"

        HStack(spacing: 10) {
            icon
                .frame(width: 26, height: 26)

            VStack(spacing: 4) {
                HStack {
                    Text(app.name)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Group {
                        if muted {
                            Text("Muted")
                        } else {
                            Text(volume, format: .percent.precision(.fractionLength(0)))
                        }
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(model.volume(for: app.id)) },
                        set: { model.setVolume(Float($0), for: app.id) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .tint(muted ? .gray : .accentColor)
                .disabled(muted)

                if let level {
                    LevelMeter(level: muted ? 0 : level, segments: 12)
                        .frame(height: 3)
                }
            }

            Button {
                withAnimation(.snappy) { model.toggleMute(app.id) }
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(muted ? Color.red : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .help(muteLabel)
            .accessibilityLabel(muteLabel)
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
