import Foundation
import CoreGraphics
import ImageIO

/// Compile with Tests/Support/{GlassProbe,TextContrastProbe}.swift.
/// Arguments: PNG scale textX textY textWidth textHeight backgroundX backgroundY.
@main
struct ProbeNativeTextContrast {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 9,
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "NativeTextContrast", code: 2)
        }
        let numbers = try args[2...].map { value -> Double in
            guard let n = Double(value) else { throw NSError(domain: "NativeTextContrast", code: 2) }
            return n
        }
        guard let result = TextContrastProbe.measure(image, scale: numbers[0],
            text: CGRect(x: numbers[1], y: numbers[2], width: numbers[3], height: numbers[4]),
            background: CGPoint(x: numbers[5], y: numbers[6])) else {
            throw NSError(domain: "NativeTextContrast", code: 2)
        }
        let data = try JSONSerialization.data(withJSONObject: result.dictionary, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        exit(result.ratio >= 4.5 ? 0 : 1)
    }
}
