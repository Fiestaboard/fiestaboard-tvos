import CoreGraphics
import Foundation

/// Measures a glass panel laid over the parity fixture's red/blue stripes.
///
/// Pure CoreGraphics, shared by the unit-test host (`drawHierarchy` shots)
/// and the UI-test runner (`XCUIScreen` shots), which does not link the app.
///
/// For sample columns across the panel's middle it reads the pixel inside
/// the panel and the raw backdrop at the same x just above the panel, then
/// keeps only columns whose backdrop is clearly red or clearly blue.
/// - `followsBackdrop`: mean (r − b) inside over red columns minus the same
///   over blue columns. ≈0 for an opaque panel, ≈510 for no panel at all.
/// - `alteredFromBackdrop`: mean per-channel |inside − backdrop|. ≈0 when
///   nothing is composited over the stripes.
struct GlassMeasurement: Equatable {
    var samples: Int
    var redColumns: Int
    var blueColumns: Int
    var followsBackdrop: Double
    var alteredFromBackdrop: Double

    /// Translucent: the backdrop shows through, and something sits on it.
    var isTranslucentGlass: Bool {
        followsBackdrop > 40 && followsBackdrop < 480 && alteredFromBackdrop > 8
    }

    var dictionary: [String: Any] {
        ["samples": samples, "redColumns": redColumns, "blueColumns": blueColumns,
         "followsBackdrop": (followsBackdrop * 10).rounded() / 10,
         "alteredFromBackdrop": (alteredFromBackdrop * 10).rounded() / 10,
         "isTranslucentGlass": isTranslucentGlass]
    }
}

enum GlassProbe {
    /// - Parameters:
    ///   - image: the full-screen shot.
    ///   - scale: pixels per point in `image`.
    ///   - panel: the glass panel's frame in points (screen space).
    static func measure(_ image: CGImage, scale: CGFloat, panel: CGRect) -> GlassMeasurement? {
        guard let pixels = RGBA(image) else { return nil }
        let inset: CGFloat = 40
        let insideY = panel.midY
        let backdropY = panel.minY - 30
        guard backdropY > 0, panel.width > inset * 2 else { return nil }

        var red: [(Int, Int, Int)] = []
        var blue: [(Int, Int, Int)] = []
        var altered = 0.0
        var x = panel.minX + inset
        while x < panel.maxX - inset {
            defer { x += 4 }
            guard let raw = pixels.at(Int(x * scale), Int(backdropY * scale)),
                  let inside = pixels.at(Int(x * scale), Int(insideY * scale)) else { continue }
            let isRed = raw.0 > 200 && raw.2 < 60
            let isBlue = raw.2 > 200 && raw.0 < 60
            guard isRed || isBlue else { continue }
            if isRed { red.append(inside) } else { blue.append(inside) }
            altered += Double(abs(inside.0 - raw.0) + abs(inside.1 - raw.1) + abs(inside.2 - raw.2)) / 3
        }
        guard !red.isEmpty, !blue.isEmpty else { return nil }
        func meanRB(_ s: [(Int, Int, Int)]) -> Double { Double(s.map { $0.0 - $0.2 }.reduce(0, +)) / Double(s.count) }
        let n = red.count + blue.count
        return GlassMeasurement(samples: n, redColumns: red.count, blueColumns: blue.count,
                                followsBackdrop: meanRB(red) - meanRB(blue),
                                alteredFromBackdrop: altered / Double(n))
    }

    /// Mean absolute per-channel difference between two shots inside `rect`
    /// (points). Used to show a focus state changed the pixels.
    static func meanDifference(_ a: CGImage, _ b: CGImage, scale: CGFloat, in rect: CGRect) -> Double? {
        guard let pa = RGBA(a), let pb = RGBA(b) else { return nil }
        var total = 0.0, count = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                if let p = pa.at(Int(x * scale), Int(y * scale)), let q = pb.at(Int(x * scale), Int(y * scale)) {
                    total += Double(abs(p.0 - q.0) + abs(p.1 - q.1) + abs(p.2 - q.2)) / 3
                    count += 1
                }
                x += 4
            }
            y += 4
        }
        return count == 0 ? nil : total / Double(count)
    }
}

/// An image redrawn into 8-bit sRGB RGBA so samples are comparable whatever
/// the source's colour space (screenshots may be Display P3).
struct RGBA {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        self.width = width
        self.height = height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        data = buffer
    }

    /// Top-left origin.
    func at(_ x: Int, _ y: Int) -> (Int, Int, Int)? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let o = (y * width + x) * 4
        return (Int(data[o]), Int(data[o + 1]), Int(data[o + 2]))
    }
}
