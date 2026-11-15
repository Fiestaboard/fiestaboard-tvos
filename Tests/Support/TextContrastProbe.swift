import CoreGraphics
import Foundation

/// Reads core glyph pixels from the actual native text bounds. Background
/// and antialiased fringe pixels are excluded before selecting the modal ink.
/// Shared by native UI tests and the retained-capture command-line verifier.
enum TextContrastProbe {
    struct Measurement {
        let foreground: [Int]
        let background: [Int]
        let corePixels: Int
        let ratio: Double
        var dictionary: [String: Any] {
            ["foreground": foreground, "background": background,
             "corePixels": corePixels, "ratio": ratio]
        }
    }

    static func measure(_ image: CGImage, scale: CGFloat, text: CGRect, background point: CGPoint) -> Measurement? {
        guard let pixels = RGBA(image), text.width > 0, text.height > 0,
              let ground = pixels.at(Int(point.x * scale), Int(point.y * scale)) else { return nil }
        let bg = [ground.0, ground.1, ground.2]
        var ink: [Int: Int] = [:]
        for y in Int(floor(text.minY * scale))..<Int(ceil(text.maxY * scale)) {
            for x in Int(floor(text.minX * scale))..<Int(ceil(text.maxX * scale)) {
                guard let p = pixels.at(x, y) else { continue }
                // Near-background pixels are empty space or antialias fringe,
                // not the fully drawn foreground whose contrast is measured.
                guard max(abs(p.0 - bg[0]), abs(p.1 - bg[1]), abs(p.2 - bg[2])) > 24 else { continue }
                ink[(p.0 << 16) | (p.1 << 8) | p.2, default: 0] += 1
            }
        }
        guard let core = ink.max(by: { $0.value < $1.value }), core.value >= 20 else { return nil }
        let fg = [core.key >> 16 & 255, core.key >> 8 & 255, core.key & 255]
        let a = luminance(fg), b = luminance(bg)
        return Measurement(foreground: fg, background: bg, corePixels: core.value,
                           ratio: (max(a, b) + 0.05) / (min(a, b) + 0.05))
    }

    private static func luminance(_ rgb: [Int]) -> Double {
        let linear = rgb.map { value -> Double in
            let s = Double(value) / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }
}
