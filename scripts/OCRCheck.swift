import Foundation
import CoreImage
import ImageIO
import CoreVideo

/// Standalone macOS verification of the actual broadcast recognizer, without a screen broadcast.
@main struct OCRCheck {
    static func main() throws {
        let width = 200, height = 400
        var data = [UInt8](repeating: 235, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                data[i + 3] = 255
                if (20..<90).contains(x), (60..<140).contains(y) {
                    data[i] = 255; data[i + 1] = 255; data[i + 2] = 255
                }
                if (110..<190).contains(x), (220..<300).contains(y) {
                    data[i] = 160; data[i + 1] = 235; data[i + 2] = 110
                }
            }
        }
        let provider = CGDataProvider(data: Data(data) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let pixels = FramePixels(image)
        precondition(pixels.side(around: CGRect(x: 0.15, y: 0.72, width: 0.2, height: 0.06)) == .other, "Top white bubble must belong to the other participant")
        precondition(pixels.side(around: CGRect(x: 0.6, y: 0.32, width: 0.25, height: 0.06)) == .me, "Lower green bubble must belong to me")
        print("PASS: top/bottom pixel orientation and sender attribution")

        guard CommandLine.arguments.count > 1 else { return }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let screenshot = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, screenshot.width, screenshot.height,
            kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        precondition(result == kCVReturnSuccess)
        CIContext().render(CIImage(cgImage: screenshot), to: buffer!)
        let bottom = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : 0.6
        let lines = try FrameRecognizer().recognize(buffer!, orientation: .up, captureBottom: bottom)
        for line in lines { print(String(format: "%.3f", line.top), line.side.rawValue, line.text) }
        if let chat = ChatSceneParser.parse(lines, captureBottom: bottom) {
            print("PARSED:", chat.title, "messages:", chat.messages.count)
            precondition(chat.messages.contains(where: { $0.hasPrefix("我：") }))
            precondition(chat.messages.contains(where: { $0.hasPrefix("对方：") }))
        } else { throw NSError(domain: "OCRCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "No supported chat found"]) }
    }
}
