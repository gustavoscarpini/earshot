import AppKit
import CoreImage

/// Computes the average color of an artwork image, for the now playing
/// header's ambient background (DESIGN §13).
enum ArtworkColor {
    /// The average color of the encoded image (PNG, JPEG, ...), using the
    /// `CIAreaAverage` filter.
    ///
    /// Not cheap, so callers compute it once per artwork change.
    ///
    /// - Returns: An opaque color, or `nil` when the data is not a decodable
    ///   image.
    static func average(of imageData: Data) -> NSColor? {
        guard
            let input = CIImage(data: imageData),
            !input.extent.isInfinite,
            !input.extent.isEmpty,
            let output = CIFilter(
                name: "CIAreaAverage",
                parameters: [
                    kCIInputImageKey: input,
                    kCIInputExtentKey: CIVector(cgRect: input.extent)
                ]
            )?.outputImage
        else {
            return nil
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return NSColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }
}
