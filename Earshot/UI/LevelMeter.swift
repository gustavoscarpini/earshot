import SwiftUI

/// A segmented level meter: green up to 65%, yellow up to 85%, red above.
///
/// `level` is `0...1`. Segments light up from the left as the level reaches
/// their threshold; the caller sets the height.
struct LevelMeter: View {
    let level: Float
    var segments = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                let threshold = Float(index + 1) / Float(segments)
                RoundedRectangle(cornerRadius: 1)
                    .fill(level >= threshold ? color(for: threshold) : Color.primary.opacity(0.1))
            }
        }
        .animation(.linear(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }

    private func color(for threshold: Float) -> Color {
        switch threshold {
        case ..<0.65: .green
        case ..<0.85: .yellow
        default: .red
        }
    }
}
