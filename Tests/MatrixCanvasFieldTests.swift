import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class MatrixCanvasFieldTests: XCTestCase {
    /// Fill only adds the surrounding unlit field: every source pixel must
    /// match Fit, even at fractional pitch, with a shifted phase and round LEDs.
    func testDenseFillPreservesEverySourcePixelAndLastCell() throws {
        for shape in ["square", "round"] {
            let display = try JSONDecoder().decode(MatrixDisplay.self, from: Data("""
                {"geometry":{"kind":"pixels","width":192,"height":720},
                 "appearance":{"pixelShape":"\(shape)","dotRatio":0.82,"offColor":"#1a1a1a"}}
                """.utf8))
            var pixels = [UInt32](repeating: 0, count: 192 * 720)
            for index in stride(from: 0, to: pixels.count, by: 17) { pixels[index] = 0xeb4034 }
            pixels[pixels.count - 1] = 0x00ff00
            let raster = MatrixRaster(width: 192, height: 720, pixels: pixels, text: "")
            let fit = try render(raster, display: display, sizing: .fitPanel)
            let fill = try render(raster, display: display, sizing: .fillTV)
            // Pitch 1.5; source starts at x=816+2.25 and ends at1106.25.
            // Compare interior pixels to exclude fractional clipping edges.
            for y in 0..<1080 {
                let start = (y * 1920 + 820) * 4
                let end = (y * 1920 + 1104) * 4
                XCTAssertEqual(Array(fill[start..<end]), Array(fit[start..<end]))
            }
            let last = (1079 * 1920 + 1105) * 4
            XCTAssertGreaterThan(fill[last + 1], 50, "the last source LED remains visible")
            XCTAssertEqual(fill[3], 255, "the field covers the viewport edge")
            XCTAssertGreaterThan(fill[0] + fill[4], 0, "Fill adds unlit LEDs outside the source")
            XCTAssertEqual(fit[0], 0, "Fit keeps the surround black")
            let offPattern = (0..<9).map { fill[(10 * 1920 + $0) * 4] }
            XCTAssertGreaterThan(Set(offPattern).count, 1,
                                 "the surrounding dots stay sharp instead of averaging into a flat gray field")
        }
    }

    private func render(_ raster: MatrixRaster, display: MatrixDisplay, sizing: MatrixSizing) throws -> [UInt8] {
        let content = Canvas { context, size in
            MatrixCanvas.paint(raster, display: display, size: size, lighting: true,
                               presentation: .init(sizing: sizing), drift: .init(x: 2.25, y: 0), in: &context)
        }.frame(width: 1920, height: 1080).background(Color.black)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.isOpaque = true
        let image = try XCTUnwrap(renderer.cgImage)
        var bytes = [UInt8](repeating: 0, count: 1920 * 1080 * 4)
        let bitmap = try XCTUnwrap(CGContext(data: &bytes, width: 1920, height: 1080,
            bitsPerComponent: 8, bytesPerRow: 1920 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        return bytes
    }
}
