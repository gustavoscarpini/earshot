import AppKit
import SwiftUI

/// The panel's title row: the "Earshot" heading.
struct PanelTitle: View {
    var body: some View {
        Text("Earshot")
            .font(.headline)
    }
}

/// The top of the panel while something is playing: the title row, artwork,
/// title, artist, source badge, progress bar and transport buttons, on a
/// background tinted with the artwork's average color (DESIGN §13).
struct NowPlayingHeader: View {
    let model: NowPlayingModel

    var body: some View {
        if let info = model.info {
            VStack(alignment: .leading, spacing: 12) {
                PanelTitle()

                HStack(spacing: 12) {
                    artwork
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        if let artist = info.artist {
                            Text(artist)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let sourceName = model.sourceName {
                            SourceBadge(name: sourceName, icon: model.appIcon)
                                .padding(.top, 4)
                        }
                    }
                    Spacer(minLength: 0)
                }

                NowPlayingProgress(info: info)

                HStack(spacing: 18) {
                    Spacer()
                    TransportButton(
                        symbol: "backward.fill",
                        label: "Previous track",
                        action: model.previousTrack
                    )
                    TransportButton(
                        symbol: info.isPlaying ? "pause.fill" : "play.fill",
                        label: info.isPlaying ? "Pause" : "Play",
                        prominent: true,
                        action: model.togglePlayPause
                    )
                    TransportButton(
                        symbol: "forward.fill",
                        label: "Next track",
                        action: model.nextTrack
                    )
                    Spacer()
                }
            }
            .padding(14)
            .background {
                ZStack {
                    ambient
                    LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
                }
                .animation(.easeInOut(duration: 0.6), value: model.ambientColor)
            }
        }
    }

    /// The artwork's average color, or a soft accent tint without artwork.
    private var ambient: Color {
        model.ambientColor.map { Color(nsColor: $0).opacity(0.55) } ?? Color.accentColor.opacity(0.35)
    }

    /// The artwork, else the app icon, else a generic placeholder.
    @ViewBuilder private var artwork: some View {
        if let image = model.artwork ?? model.appIcon {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.secondary.opacity(0.2)
                Image(systemName: "music.note")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// What the panel shows in place of the header while nothing is playing.
struct EmptyNowPlaying: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading) {
                Text("Nothing playing")
                    .font(.headline)
                Text("Press play in any app to control it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }
}

/// The progress bar with the elapsed time on the left and the remaining time on
/// the right. Hidden when the track length is unknown. Ticks once a second, and
/// only while playing.
private struct NowPlayingProgress: View {
    let info: NowPlayingInfo

    var body: some View {
        if let duration = info.duration, duration > 0 {
            if info.isPlaying {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    bar(elapsed: info.elapsed(at: context.date) ?? 0, duration: duration)
                }
            } else {
                bar(elapsed: info.elapsed(at: .now) ?? 0, duration: duration)
            }
        }
    }

    private func bar(elapsed: TimeInterval, duration: TimeInterval) -> some View {
        VStack(spacing: 4) {
            ProgressView(value: min(max(elapsed, 0), duration), total: duration)
                .progressViewStyle(.linear)
                .tint(.white.opacity(0.9))
            HStack {
                Text(NowPlayingInfo.clockString(elapsed))
                Spacer()
                Text("-" + NowPlayingInfo.clockString(duration - elapsed))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

/// A capsule with the playing app's small icon and name.
private struct SourceBadge: View {
    let name: String
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 12, height: 12)
            }
            Text(name)
                .lineLimit(1)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.white.opacity(0.12), in: Capsule())
    }
}

/// A round transport button: a circle appears on hover and the button grows a
/// little. The prominent one (play/pause) is a white disc with a black glyph.
private struct TransportButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var prominent = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 18 : 15, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: prominent ? 40 : 30, height: prominent ? 40 : 30)
                .foregroundStyle(prominent ? Color.black : Color.primary)
                .background {
                    Circle()
                        .fill(prominent ? Color.white : Color.white.opacity(hovering ? 0.15 : 0))
                }
                .scaleEffect(hovering ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.12)) { hovering = isHovering }
        }
        .help(label)
        .accessibilityLabel(label)
    }
}
