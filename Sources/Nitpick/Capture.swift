import UIKit

/// Makes the picture that goes with a piece of feedback.
///
/// It draws the app's own window with `drawHierarchy`. The component's windows are separate
/// `UIWindow`s, so the tab, the pointing layer and the panel are never part of it.
/// Masked frames and secure text fields become black boxes.
@MainActor
enum Capture {
    static let maxLongSide: CGFloat = 1600
    /// The first quality tried. Lower when the file is too large.
    static let jpegQuality: CGFloat = 0.7
    static let minimumJPEGQuality: CGFloat = 0.1
    /// The file must be smaller than this: 1 MB.
    static let maxBytes = 1_000_000

    struct Result {
        var jpeg: Data
        /// Size in pixels of the JPEG.
        var pixelSize: CGSize
        /// Whether `drawHierarchy` reported complete drawing.
        var drewCompletely: Bool
    }

    /// Scale such that the longest side is at most 1600 pixels, also after rounding up: 1194 * (1600 / 1194)
    /// is 1600.0000000000002 in floating point, and the renderer rounds a fraction of a pixel up to 1601.
    /// So the scale goes down by the smallest steps until both sides, rounded up, fit.
    static func outputScale(for size: CGSize, screenScale: CGFloat) -> CGFloat {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return screenScale }
        var scale = min(screenScale, maxLongSide / longest)
        var steps = 0
        while pixelSide(longest, scale: scale) > Int(maxLongSide), steps < 64 {
            scale = scale.nextDown
            steps += 1
        }
        return scale
    }

    /// Pixels of one side at a scale, rounded up the way the image renderer does.
    static func pixelSide(_ points: CGFloat, scale: CGFloat) -> Int {
        Int((points * scale).rounded(.up))
    }

    /// Frames (in window points) of every `SecureField` and secure `UITextField` in the window.
    static func secureFieldFrames(in window: UIWindow) -> [CGRect] {
        var frames: [CGRect] = []
        func walk(_ view: UIView) {
            if let field = view as? UITextField, field.isSecureTextEntry, !field.isHidden {
                frames.append(field.convert(field.bounds, to: window))
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(window)
        return frames
    }

    static func capture(window: UIWindow, maskFrames: [CGRect]) -> Result? {
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = outputScale(for: bounds.size, screenScale: window.screen.scale)
        format.opaque = true
        let blackBoxes = maskFrames + secureFieldFrames(in: window)
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        var complete = false
        let image = renderer.image { context in
            complete = window.drawHierarchy(in: bounds, afterScreenUpdates: true)
            if !complete {
                // drawHierarchy says false when image data is missing (window not on screen).
                // Fall back to the layer tree: no web or video content, but the rest is there.
                window.layer.render(in: context.cgContext)
            }
            UIColor.black.setFill()
            for frame in blackBoxes {
                context.fill(frame.insetBy(dx: -1, dy: -1))
            }
        }
        guard let encoded = encodeJPEG(image) else { return nil }
        return Result(jpeg: encoded.data, pixelSize: encoded.pixelSize, drewCompletely: complete)
    }

    /// JPEG smaller than `maxBytes`: quality 0.7 first, then lower in steps of 0.1 until it fits.
    /// Only when even the lowest quality is too large (a very noisy picture) is the picture made smaller.
    static func encodeJPEG(_ image: UIImage, maxBytes: Int = Capture.maxBytes) -> (data: Data, pixelSize: CGSize)? {
        var current = image
        while true {
            var quality = jpegQuality
            while true {
                guard let data = current.jpegData(compressionQuality: quality) else { return nil }
                // The pixels of the bitmap itself, not points times scale (which can differ by a fraction).
                let pixels = current.cgImage.map { CGSize(width: $0.width, height: $0.height) }
                    ?? CGSize(width: current.size.width * current.scale, height: current.size.height * current.scale)
                if data.count < maxBytes { return (data, pixels) }
                if quality <= minimumJPEGQuality + 0.001 {
                    if min(pixels.width, pixels.height) < 64 { return (data, pixels) }
                    break
                }
                quality = max(minimumJPEGQuality, quality - 0.1)
            }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let smaller = CGSize(width: (current.size.width * current.scale * 0.8).rounded(), height: (current.size.height * current.scale * 0.8).rounded())
            let source = current
            current = UIGraphicsImageRenderer(size: smaller, format: format).image { _ in source.draw(in: CGRect(origin: .zero, size: smaller)) }
        }
    }
}
