import Testing
import UIKit
@testable import Nitpick

@MainActor
private func makeWindow(size: CGSize = CGSize(width: 200, height: 400), _ build: (UIView) -> Void) -> UIWindow {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(origin: .zero, size: size))
    window.frame = CGRect(origin: .zero, size: size)
    let controller = UIViewController()
    controller.view.backgroundColor = .white
    window.rootViewController = controller
    window.isHidden = false
    build(controller.view)
    window.layoutIfNeeded()
    return window
}

private func pixel(_ image: UIImage, atPoint point: CGPoint, windowSize: CGSize = CGSize(width: 200, height: 400)) -> (r: Int, g: Int, b: Int) {
    let cg = image.cgImage!
    let x = Int(point.x * CGFloat(cg.width) / windowSize.width)
    let y = Int(point.y * CGFloat(cg.height) / windowSize.height)
    var data = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
    return (Int(data[0]), Int(data[1]), Int(data[2]))
}

/// Pixel size of a JPEG, read from the file and not from what the code says.
private func pixelSize(ofJPEG data: Data) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return (width, height)
}

/// A picture of random noise: the worst case for JPEG, far above 1 MB at quality 0.7.
private func noiseImage(width: Int, height: Int) -> UIImage {
    var generator = SystemRandomNumberGenerator()
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for index in stride(from: 0, to: bytes.count, by: 4) {
        bytes[index] = UInt8.random(in: 0...255, using: &generator)
        bytes[index + 1] = UInt8.random(in: 0...255, using: &generator)
        bytes[index + 2] = UInt8.random(in: 0...255, using: &generator)
        bytes[index + 3] = 255
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return UIImage(cgImage: cg, scale: 1, orientation: .up)
}

@MainActor
@Suite("Schermafbeelding", .serialized)
struct CaptureTests {
    @Test func aNoisyPictureIsEncodedBelow1MBWithLowerQuality() throws {
        let image = noiseImage(width: 1600, height: 739)
        let atFirstQuality = try #require(image.jpegData(compressionQuality: Capture.jpegQuality))
        #expect(atFirstQuality.count > Capture.maxBytes, "the test picture must be too large at quality 0.7 (is \(atFirstQuality.count))")
        let encoded = try #require(Capture.encodeJPEG(image))
        #expect(encoded.data.count < 1_000_000)
        #expect(encoded.data.count < atFirstQuality.count)
        #expect(encoded.data.prefix(2) == Data([0xFF, 0xD8]))
        let size = try #require(pixelSize(ofJPEG: encoded.data))
        #expect(max(size.width, size.height) <= 1600)
        #expect(Int(encoded.pixelSize.width) == size.width && Int(encoded.pixelSize.height) == size.height)
    }

    @Test func aWindowWithNoisyContentGivesAtMost1600PixelsAndLessThan1MB() throws {
        let size = CGSize(width: 393, height: 852)
        let noise = noiseImage(width: 786, height: 1704)
        let window = makeWindow(size: size) { root in
            let view = UIImageView(image: noise)
            view.frame = CGRect(origin: .zero, size: size)
            root.addSubview(view)
        }
        let result = try #require(Capture.capture(window: window, maskFrames: []))
        #expect(result.jpeg.count < 1_000_000, "is \(result.jpeg.count) bytes")
        let pixels = try #require(pixelSize(ofJPEG: result.jpeg))
        #expect(max(pixels.width, pixels.height) <= 1600, "is \(pixels)")
        #expect(result.jpeg.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func aLargeWindowIsScaledDownToAtMost1600Pixels() throws {
        let size = CGSize(width: 1024, height: 1366)
        let window = makeWindow(size: size) { root in
            let box = UIView(frame: CGRect(x: 100, y: 100, width: 300, height: 300))
            box.backgroundColor = .systemGreen
            root.addSubview(box)
        }
        let result = try #require(Capture.capture(window: window, maskFrames: []))
        let pixels = try #require(pixelSize(ofJPEG: result.jpeg))
        #expect(max(pixels.width, pixels.height) <= 1600, "is \(pixels)")
        #expect(result.jpeg.count < 1_000_000)
    }

    @Test func outputScaleCapsTheLongestSideAt1600Pixels() {
        #expect(Capture.outputScale(for: CGSize(width: 393, height: 852), screenScale: 3) <= 1600.0 / 852.0)
        #expect(Capture.outputScale(for: CGSize(width: 200, height: 400), screenScale: 3) == 3)
        #expect(Capture.outputScale(for: CGSize(width: 1024, height: 1366), screenScale: 2) <= 1600.0 / 1366.0)
    }

    @Test func capturesTheWindowAsJPEGWithinTheSizeLimit() throws {
        let window = makeWindow(size: CGSize(width: 393, height: 852)) { root in
            let red = UIView(frame: CGRect(x: 20, y: 20, width: 100, height: 100))
            red.backgroundColor = .red
            root.addSubview(red)
        }
        let result = try #require(Capture.capture(window: window, maskFrames: []))
        #expect(result.jpeg.prefix(2) == Data([0xFF, 0xD8]))
        #expect(max(result.pixelSize.width, result.pixelSize.height) <= 1600)
        let image = try #require(UIImage(data: result.jpeg))
        let p = pixel(image, atPoint: CGPoint(x: 60, y: 60), windowSize: CGSize(width: 393, height: 852))
        #expect(p.r > 200 && p.g < 80 && p.b < 80, "expected red, got \(p)")
    }

    @Test func maskedFrameBecomesBlack() throws {
        let window = makeWindow { root in
            let red = UIView(frame: CGRect(x: 20, y: 20, width: 100, height: 100))
            red.backgroundColor = .red
            root.addSubview(red)
        }
        let mask = CGRect(x: 20, y: 20, width: 100, height: 100)
        let result = try #require(Capture.capture(window: window, maskFrames: [mask]))
        let image = try #require(UIImage(data: result.jpeg))
        let inside = pixel(image, atPoint: CGPoint(x: 70, y: 70))
        #expect(inside.r < 40 && inside.g < 40 && inside.b < 40, "mask not black: \(inside)")
        let outside = pixel(image, atPoint: CGPoint(x: 160, y: 300))
        #expect(outside.r > 220 && outside.g > 220 && outside.b > 220, "outside changed: \(outside)")
    }

    @Test func secureTextFieldBecomesBlackWithoutMarker() throws {
        let window = makeWindow { root in
            let field = UITextField(frame: CGRect(x: 20, y: 200, width: 160, height: 44))
            field.isSecureTextEntry = true
            field.text = "hunter2"
            field.backgroundColor = .yellow
            root.addSubview(field)
        }
        #expect(Capture.secureFieldFrames(in: window).count == 1)
        let result = try #require(Capture.capture(window: window, maskFrames: []))
        let image = try #require(UIImage(data: result.jpeg))
        let inside = pixel(image, atPoint: CGPoint(x: 100, y: 222))
        #expect(inside.r < 40 && inside.g < 40 && inside.b < 40, "secure field not black: \(inside)")
    }

    @Test func plainTextFieldIsNotCovered() throws {
        let window = makeWindow { root in
            let field = UITextField(frame: CGRect(x: 20, y: 200, width: 160, height: 44))
            field.backgroundColor = .yellow
            root.addSubview(field)
        }
        #expect(Capture.secureFieldFrames(in: window).isEmpty)
        let result = try #require(Capture.capture(window: window, maskFrames: []))
        let image = try #require(UIImage(data: result.jpeg))
        let inside = pixel(image, atPoint: CGPoint(x: 100, y: 222))
        #expect(inside.r > 200 && inside.g > 200 && inside.b < 120, "expected yellow: \(inside)")
    }

    @Test func windowsOfTheComponentAreNotPartOfThePicture() throws {
        // The component draws in its own windows. A window of ours with a blue box must not show up in the app window's picture.
        let app = makeWindow { _ in }
        let overlay = NitpickWindow(frame: app.frame)
        overlay.windowLevel = .alert
        let controller = UIViewController()
        controller.view.backgroundColor = .blue
        overlay.rootViewController = controller
        overlay.isHidden = false
        defer { overlay.isHidden = true }
        let result = try #require(Capture.capture(window: app, maskFrames: []))
        let image = try #require(UIImage(data: result.jpeg))
        let p = pixel(image, atPoint: CGPoint(x: 100, y: 200))
        #expect(p.b < 60 || p.r > 200, "overlay leaked into the picture: \(p)")
    }

    // MARK: Review: never 1601

    @Test func theLongestSideNeverRoundsUpPast1600() {
        // 1194 * (1600 / 1194) is 1600.0000000000002 in floating point.
        #expect(1194 * (1600.0 / 1194.0) > 1600, "the case of the review: the plain division is over")
        var worst = 0
        var checked = 0
        for longest in stride(from: 1000.0, through: 2800.0, by: 1.0) {
            for shortest in [longest * 0.46, longest * 0.7, longest] {
                for screenScale in [2.0, 3.0] {
                    let size = CGSize(width: shortest, height: longest)
                    let scale = Capture.outputScale(for: size, screenScale: screenScale)
                    let pixels = max(Capture.pixelSide(size.width, scale: scale), Capture.pixelSide(size.height, scale: scale))
                    worst = max(worst, pixels)
                    checked += 1
                    #expect(pixels <= 1600, "\(size) at \(screenScale) gives \(pixels)")
                }
            }
        }
        #expect(worst == 1600, "the cap is used, not undershot (worst \(worst) of \(checked))")
    }

    @Test func iPadWindowsOf834By1194GiveAPictureOf1600PixelsAtMost() throws {
        for size in [CGSize(width: 834, height: 1194), CGSize(width: 1194, height: 834), CGSize(width: 820, height: 1180), CGSize(width: 744, height: 1133)] {
            let window = makeWindow(size: size) { root in
                let box = UIView(frame: CGRect(x: 100, y: 100, width: 300, height: 300))
                box.backgroundColor = .systemGreen
                root.addSubview(box)
            }
            let result = try #require(Capture.capture(window: window, maskFrames: []))
            let pixels = try #require(pixelSize(ofJPEG: result.jpeg))
            #expect(max(pixels.width, pixels.height) <= 1600, "\(size): the file is \(pixels)")
            #expect(max(pixels.width, pixels.height) >= 1599, "\(size): not smaller than needed, is \(pixels)")
            #expect(Int(result.pixelSize.width) == pixels.width && Int(result.pixelSize.height) == pixels.height, "\(size): the reported size is the size of the file")
            let image = try #require(UIImage(data: result.jpeg))
            #expect(max(image.cgImage!.width, image.cgImage!.height) <= 1600)
        }
    }
}
