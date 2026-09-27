import Foundation
import Vision
import CoreImage
import ImageIO

final class FrameRecognizer {
    private let imageContext = CIContext(options: [.cacheIntermediates: false])

    func recognize(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                   captureBottom: Double) throws -> [RecognizedChatLine] {
        let source = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let extent = source.extent
        guard extent.width < extent.height, extent.width > 0 else { return [] }
        let scale = min(1, 720 / extent.width)
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let height = scaled.extent.height
        let crop = CGRect(x: 0, y: height * (1 - captureBottom), width: scaled.extent.width,
                          height: height * captureBottom).integral
        guard let image = imageContext.createCGImage(scaled, from: crop) else { return [] }
        defer { imageContext.clearCaches() }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.012
        try VNImageRequestHandler(cgImage: image).perform([request])
        let pixels = FramePixels(image)
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.35 else { return nil }
            let box = observation.boundingBox
            return RecognizedChatLine(
                text: candidate.string,
                minX: box.minX, maxX: box.maxX,
                top: (1 - box.maxY) * captureBottom,
                bottom: (1 - box.minY) * captureBottom,
                side: pixels.side(around: box)
            )
        }
    }
}

/// Bubble background is a stronger sender signal than text alignment for long messages.
struct FramePixels {
    let bytes: [UInt8]
    let width: Int
    let height: Int
    init(_ image: CGImage) {
        let width = image.width, height = image.height
        self.width = width; self.height = height
        var storage = [UInt8](repeating: 0, count: width * height * 4)
        storage.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return }
            // CGImage rows already map top-to-bottom in this bitmap buffer.
            // Flipping the drawing would invert sender sampling relative to Vision boxes.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        bytes = storage
    }
    func side(around box: CGRect) -> RecognizedChatLine.Side {
        let y = Int((1 - box.midY) * Double(height))
        // Sample the bubble padding directly beside recognized text, avoiding ink.
        let left = Int(box.minX * Double(width)) - 4
        let right = Int(box.maxX * Double(width)) + 4
        var green = 0, white = 0, darkBubble = 0
        for x in [left, left - 3, right, right + 3] {
            guard x > 0, x < width, y > 0, y < height else { continue }
            let index = (y * width + x) * 4
            let r = Double(bytes[index]) / 255, g = Double(bytes[index + 1]) / 255, b = Double(bytes[index + 2]) / 255
            if g > 0.45 && g - r > 0.12 && g - b > 0.16 { green += 1 }
            if min(r, g, b) > 0.965 { white += 1 }
            if r > 0.14 && r < 0.25 && abs(r - g) < 0.035 && abs(g - b) < 0.035 { darkBubble += 1 }
        }
        if green >= 2 { return .me }
        if (white >= 2 || darkBubble >= 2), box.minX < 0.35 { return .other }
        return .none
    }
}
