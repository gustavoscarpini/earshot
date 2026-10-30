import AppKit

/// Draws the menu bar icon for a `MenuBarGlyph`.
///
/// Every image is a template, so the menu bar tints it for light and dark
/// wallpapers and for the pressed state, like the system's own items. The
/// equalizer is drawn into a 2× bitmap rather than with a drawing handler, so
/// no non-Sendable state is captured.
enum MenuBarIconRenderer {
    /// The symbol point size, close to the system's own menu bar items.
    private static let pointSize: CGFloat = 14

    /// The image for `glyph`.
    @MainActor
    static func image(for glyph: MenuBarGlyph) -> NSImage {
        switch glyph {
        case .micMuted:
            symbol("mic.slash.fill")
        case .outputMuted:
            symbol("speaker.slash.fill")
        case .playing:
            equalizer(EqualizerLevels.bars)
        case .device(let name):
            symbol(name)
        case .speaker(let volume):
            symbol("speaker.wave.3.fill", variableValue: volume)
        }
    }

    private static func symbol(_ name: String, variableValue: Double? = nil) -> NSImage {
        let base = if let variableValue {
            NSImage(systemSymbolName: name, variableValue: variableValue, accessibilityDescription: nil)
        } else {
            NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let image = base?.withSymbolConfiguration(configuration)
            ?? NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)
            ?? NSImage()
        image.isTemplate = true
        return image
    }

    private static func equalizer(_ levels: [Double]) -> NSImage {
        let barWidth: CGFloat = 2.5
        let gap: CGFloat = 1.5
        let height: CGFloat = 16
        let maxBar: CGFloat = 12
        let minBar: CGFloat = 3
        let scale: CGFloat = 2
        let count = CGFloat(levels.count)
        let width = count * barWidth + max(count - 1, 0) * gap

        guard
            width > 0,
            let context = CGContext(
                data: nil,
                width: Int((width * scale).rounded(.up)),
                height: Int(height * scale),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return NSImage() }

        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        // Core Graphics' origin is bottom-left, so the bars share a baseline
        // and grow upwards.
        let baseline = (height - maxBar) / 2
        for (index, level) in levels.enumerated() {
            let barHeight = minBar + (maxBar - minBar) * CGFloat(min(max(level, 0), 1))
            let rect = CGRect(x: CGFloat(index) * (barWidth + gap), y: baseline, width: barWidth, height: barHeight)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        }
        context.fillPath()

        guard let cgImage = context.makeImage() else { return NSImage() }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        image.isTemplate = true
        return image
    }
}
