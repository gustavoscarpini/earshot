#!/usr/bin/env swift
// Generates the Earshot app icon: a sound source dot with fading wave arcs on
// an indigo-to-violet squircle. Everything is drawn with paths (no SF Symbols,
// whose license forbids them in app icons).
//
// Usage: swift Scripts/make-app-icon.swift
// Writes the ten macOS PNG sizes and Contents.json into
// Earshot/Resources/Assets.xcassets/AppIcon.appiconset.

import AppKit
import CoreGraphics

let outDir = "Earshot/Resources/Assets.xcassets/AppIcon.appiconset"
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, a])!
}

/// Continuous-corner rounded rectangle (superellipse corners, like Apple's icon shape).
func squircle(_ r: CGRect, radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k: CGFloat = 1.2 * radius   // corner extent along each edge
    let c: CGFloat = 0.62            // control point factor
    let minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
    p.move(to: CGPoint(x: minX + k, y: minY))
    p.addLine(to: CGPoint(x: maxX - k, y: minY))
    p.addCurve(to: CGPoint(x: maxX, y: minY + k),
               control1: CGPoint(x: maxX - k * (1 - c) , y: minY),
               control2: CGPoint(x: maxX, y: minY + k * (1 - c)))
    p.addLine(to: CGPoint(x: maxX, y: maxY - k))
    p.addCurve(to: CGPoint(x: maxX - k, y: maxY),
               control1: CGPoint(x: maxX, y: maxY - k * (1 - c)),
               control2: CGPoint(x: maxX - k * (1 - c), y: maxY))
    p.addLine(to: CGPoint(x: minX + k, y: maxY))
    p.addCurve(to: CGPoint(x: minX, y: maxY - k),
               control1: CGPoint(x: minX + k * (1 - c), y: maxY),
               control2: CGPoint(x: minX, y: maxY - k * (1 - c)))
    p.addLine(to: CGPoint(x: minX, y: minY + k))
    p.addCurve(to: CGPoint(x: minX + k, y: minY),
               control1: CGPoint(x: minX, y: minY + k * (1 - c)),
               control2: CGPoint(x: minX + k * (1 - c), y: minY))
    p.closeSubpath()
    return p
}

/// Draws the icon in a 1024-unit coordinate space (origin bottom-left).
func draw(_ ctx: CGContext) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(tile, radius: 185)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0, 0, 0, 0.45))
    ctx.addPath(shape); ctx.setFillColor(rgb(40, 24, 90)); ctx.fillPath()
    ctx.restoreGState()

    // Background gradient, clipped to the tile.
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: space,
                        colors: [rgb(124, 92, 255), rgb(74, 52, 190), rgb(34, 22, 92)] as CFArray,
                        locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 700, y: 100),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Soft glow behind the source.
    let glow = CGGradient(colorsSpace: space,
                          colors: [rgb(255, 140, 110, 0.38), rgb(255, 140, 110, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 350, y: 512), startRadius: 0,
                           endCenter: CGPoint(x: 350, y: 512), endRadius: 420, options: [])
    ctx.restoreGState()

    // Thin top highlight: the sliver of the tile not covered by a copy shifted down.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.addPath(shape.copy(using: [CGAffineTransform(translationX: 0, y: -5)])!)
    ctx.clip(using: .evenOdd)
    ctx.addPath(shape); ctx.clip()
    let hl = CGGradient(colorsSpace: space,
                        colors: [rgb(255, 255, 255, 0.45), rgb(255, 255, 255, 0)] as CFArray,
                        locations: [0, 0.5])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // Sound source: warm coral dot.
    let center = CGPoint(x: 340, y: 512)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(20, 8, 60, 0.45))
    let dot = CGGradient(colorsSpace: space,
                         colors: [rgb(255, 176, 120), rgb(255, 98, 112)] as CFArray, locations: [0, 1])!
    ctx.addEllipse(in: CGRect(x: center.x - 82, y: center.y - 82, width: 164, height: 164))
    ctx.clip()
    ctx.drawLinearGradient(dot, start: CGPoint(x: center.x, y: center.y + 82),
                           end: CGPoint(x: center.x, y: center.y - 82), options: [])
    ctx.restoreGState()

    // Wave arcs opening to the right, fading out.
    let radii: [CGFloat] = [165, 280, 395]
    let alphas: [CGFloat] = [1.0, 0.72, 0.42]
    let half: CGFloat = 46 * .pi / 180
    ctx.setLineCap(.round)
    ctx.setLineWidth(56)
    for (r, a) in zip(radii, alphas) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: rgb(20, 8, 60, 0.3 * a))
        ctx.setStrokeColor(rgb(255, 255, 255, a))
        ctx.addArc(center: center, radius: r, startAngle: -half, endAngle: half, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = gc.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(ctx)
    return rep.representation(using: .png, properties: [:])!
}

var entries: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try! render(pixels: size * scale).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
        entries.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
    }
}
let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: "\(outDir)/Contents.json"))
print("Wrote \(entries.count) icons to \(outDir)")
