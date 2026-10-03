import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// Makes a two second video of moving color blocks, so the demo needs no bundled media.
enum VideoMaker {
    static func makeIfNeeded() async -> URL {
        let url = URL.temporaryDirectory.appending(path: "demo-video.mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let width = 320, height = 480, fps: Int32 = 15, frames = 30
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return url }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try? await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                context.setFillColor(CGColor(red: 0.05, green: 0.4, blue: 0.3, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.1, alpha: 1))
                context.fill(CGRect(x: 10 + frame * 8, y: 150, width: 70, height: 70))
                context.setFillColor(CGColor(red: 1, green: 0.29, blue: 0.11, alpha: 1))
                context.fill(CGRect(x: 240 - frame * 6, y: 300, width: 60, height: 60))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}
