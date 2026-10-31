import AppKit

/// Draws the menu bar icon for a `MenuBarGlyph`.
///
/// Every image is a template, so the menu bar tints it for light and dark
/// wallpapers and for the pressed state, like the system's own items. The
/// equalizer is drawn into a 2× bitmap rather than with a drawing handler, so
/// no non-Sendable state is captured.
enum MenuBarIconRenderer {
    /// The symbol point size, close to the system's own menu bar items.
    private static let glyphPointSize: CGFloat = 14

    /// The point size of the muted microphone badge.
    private static let badgePointSize: CGFloat = 11

    /// The menu bar icon height.
    private static let iconHeight: CGFloat = 16

    /// The space between the glyph and the badge.
    private static let badgeGap: CGFloat = 3

    /// The image for `icon`: the glyph, then the muted microphone badge to its
    /// right when `icon.isMicMuted`, composited into one template image.
    @MainActor
    static func image(for icon: MenuBarIcon) -> NSImage {
        let glyph = image(for: icon.glyph)
        guard icon.isMicMuted else { return glyph }
        let badge = symbol("mic.slash.fill", pointSize: badgePointSize)
        return composite(glyph, badge)
    }

    /// Draws `trailing` to the right of `leading`, both vertically centered,
    /// into a 2× bitmap (no drawing handler, so nothing non-Sendable is
    /// captured) and marks the result as a template.
    private static func composite(_ leading: NSImage, _ trailing: NSImage) -> NSImage {
        let width = leading.size.width + badgeGap + trailing.size.width
        let height = max(iconHeight, leading.size.height, trailing.size.height)
        let scale: CGFloat = 2
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int((width * scale).rounded(.up)),
                pixelsHigh: Int((height * scale).rounded(.up)),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else { return leading }
        // The size in points must be set before the context is created: the
        // context derives its 2× scale from it.
        rep.size = NSSize(width: width, height: height)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return leading }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        leading.draw(in: NSRect(x: 0, y: (height - leading.size.height) / 2, width: leading.size.width, height: leading.size.height))
        trailing.draw(in: NSRect(
            x: leading.size.width + badgeGap,
            y: (height - trailing.size.height) / 2,
            width: trailing.size.width,
            height: trailing.size.height
        ))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    @MainActor
    private static func image(for glyph: MenuBarGlyph) -> NSImage {
        switch glyph {
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

    private static func symbol(_ name: String, pointSize: CGFloat = glyphPointSize, variableValue: Double? = nil) -> NSImage {
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
