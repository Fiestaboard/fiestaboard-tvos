import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardTV

/// DD24: LED dots are FiestaUI's `traceDot`. A dot of 6 device pixels or more
/// is a square with corners rounded to 0.15 of the dot; smaller dots stay
/// square; "round" stays an oval. Every other shape, the hub's "square"
/// default included, takes the rounded path. Glow and lens follow the dot.
@MainActor
final class LedDotShapeTests: XCTestCase {

    nonisolated private static let red: UInt32 = 0xFF0000

    private func display(shape: String? = "square", dotRatio: Double = 0.82) throws -> MatrixDisplay {
        var appearance: [String: Any] = ["dotRatio": dotRatio, "offColor": "#1a1a1a", "substrateColor": "#000000"]
        if let shape { appearance["pixelShape"] = shape }
        let json = try JSONSerialization.data(withJSONObject: ["appearance": appearance])
        return try JSONDecoder().decode(MatrixDisplay.self, from: json)
    }

    private func raster(_ width: Int, _ height: Int, lit: Set<Int> = [], color: UInt32 = red) -> MatrixRaster {
        MatrixRaster(width: width, height: height,
                     pixels: (0..<(width * height)).map { lit.contains($0) ? color : 0 }, text: "")
    }

    /// RGBA bytes of a `size`-point canvas drawn at `scale`.
    private func bytes(size: CGSize, scale: CGFloat,
                       _ draw: @escaping (inout GraphicsContext, CGSize) -> Void) throws -> [UInt8] {
        let renderer = ImageRenderer(content: Canvas { context, size in draw(&context, size) }
            .frame(width: size.width, height: size.height))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private func painted(_ raster: MatrixRaster, _ display: MatrixDisplay, size: CGSize, scale: CGFloat = 1,
                         lighting: Bool = false) throws -> [UInt8] {
        try bytes(size: size, scale: scale) { context, size in
            MatrixCanvas.paint(raster, display: display, size: size, lighting: lighting, in: &context)
        }
    }

    /// The panel's black ground with one `color` dot, as a reference painter would draw it.
    private func reference(size: CGSize, scale: CGFloat = 1, dot: CGRect, color: UInt32 = red,
                           _ shape: @escaping (CGRect) -> Path) throws -> [UInt8] {
        try bytes(size: size, scale: scale) { context, size in
            // The renderer clips to the panel's bounds first; so does this.
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            context.fill(shape(dot), with: .color(Color(red: Double((color >> 16) & 255) / 255,
                                                         green: Double((color >> 8) & 255) / 255,
                                                         blue: Double(color & 255) / 255)))
        }
    }

    private func pixel(_ data: [UInt8], width: Int, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let i = (y * width + x) * 4
        return (data[i], data[i + 1], data[i + 2])
    }

    // MARK: The radius

    /// One 82-point lit dot (a 100-point pitch, ratio 0.82, inset 9).
    func testDotsOfSixPixelsOrMoreAreRoundedToFifteenHundredthsOfTheDot() throws {
        let size = CGSize(width: 100, height: 100)
        let dot = CGRect(x: 9, y: 9, width: 82, height: 82)
        let app = try painted(raster(1, 1, lit: [0]), display(), size: size)
        XCTAssertEqual(app, try reference(size: size, dot: dot) { Path(roundedRect: $0, cornerRadius: 82 * 0.15, style: .circular) },
                       "a lit dot is roundRect(0.15 × dot)")
        for ratio in [0, 0.10, 0.20] {
            XCTAssertNotEqual(app, try reference(size: size, dot: dot) { Path(roundedRect: $0, cornerRadius: 82 * ratio, style: .circular) },
                              "the corner is 0.15 of the dot, not \(ratio)")
        }
        XCTAssertEqual(pixel(app, width: 100, x: 9, y: 9).r, 0, "the true corner is the #000 gap")
        XCTAssertEqual(pixel(app, width: 100, x: 50, y: 50).r, 255)
    }

    /// FiestaUI's threshold is in device pixels: `size >= 6`. Each dot
    /// sits on whole device pixels (a 2 px inset), so the painter must match
    /// a reference painter byte for byte: the rounded one at 6 px, the
    /// square one at 5 px.
    func testTheSixPixelThresholdRoundsAtSixAndKeepsSmallerDotsSquare() throws {
        let cases: [(side: CGFloat, scale: CGFloat, ratio: Double, rounds: Bool)] = [
            (10, 1, 0.6, true),        // 6 px dot at scale 1
            (9, 1, 5.0 / 9, false),    // 5 px dot at scale 1
            (5, 2, 0.6, true),         // 3 pt = 6 px at scale 2
            (4.5, 2, 5.0 / 9, false)   // 2.5 pt = 5 px at scale 2
        ]
        for c in cases {
            let size = CGSize(width: c.side, height: c.side)
            let dot = CGRect(x: 2 / c.scale, y: 2 / c.scale, width: c.side * c.ratio, height: c.side * c.ratio)
            let pixels = Int((dot.width * c.scale).rounded())
            let app = try painted(raster(1, 1, lit: [0]), display(dotRatio: c.ratio), size: size, scale: c.scale)
            let square = try reference(size: size, scale: c.scale, dot: dot) { Path($0) }
            let rounded = try reference(size: size, scale: c.scale, dot: dot) {
                Path(roundedRect: $0, cornerRadius: $0.width * 0.15, style: .circular)
            }
            XCTAssertNotEqual(square, rounded, "the references must differ, or this proves nothing")
            if c.rounds {
                XCTAssertEqual(app, rounded, "a \(pixels) px dot at scale \(c.scale) rounds")
            } else {
                XCTAssertEqual(app, square, "a \(pixels) px dot at scale \(c.scale) stays square")
            }
        }
    }

    /// The rule itself, in device pixels (FiestaUI `size >= 6`).
    func testTheCornerRadiusIsFifteenHundredthsOfADotOfSixPixelsOrMore() {
        XCTAssertEqual(LedDot.cornerRadius(dot: 24.6, scale: 2), 24.6 * 0.15, accuracy: 1e-9)
        XCTAssertEqual(LedDot.cornerRadius(dot: 6, scale: 1), 0.9, accuracy: 1e-9)
        XCTAssertEqual(LedDot.cornerRadius(dot: 3, scale: 2), 0.45, accuracy: 1e-9)
        XCTAssertEqual(LedDot.cornerRadius(dot: 5.99, scale: 1), 0)
        XCTAssertEqual(LedDot.cornerRadius(dot: 2.99, scale: 2), 0)
    }

    // MARK: Shapes

    func testRoundDotsStayOvalAndUnknownShapesTakeTheRoundedSquarePath() throws {
        let size = CGSize(width: 100, height: 100)
        let dot = CGRect(x: 9, y: 9, width: 82, height: 82)
        let rounded = try reference(size: size, dot: dot) { Path(roundedRect: $0, cornerRadius: 82 * 0.15, style: .circular) }
        XCTAssertEqual(try painted(raster(1, 1, lit: [0]), display(shape: "round"), size: size),
                       try reference(size: size, dot: dot) { Path(ellipseIn: $0) }, "round stays an oval")
        XCTAssertEqual(try painted(raster(1, 1, lit: [0]), display(shape: "hexagon"), size: size), rounded,
                       "a shape the app doesn't know renders as the hub's square default")
        XCTAssertEqual(try painted(raster(1, 1, lit: [0]), display(shape: nil), size: size), rounded,
                       "no shape is the hub's square default")
    }

    func testUnlitDotsAreRoundedTooAndTheGapStaysBlack() throws {
        let size = CGSize(width: 100, height: 100)
        let app = try painted(raster(1, 1), display(), size: size)
        let dot = CGRect(x: 9, y: 9, width: 82, height: 82)
        XCTAssertEqual(app, try reference(size: size, dot: dot, color: 0x1A1A1A) {
            Path(roundedRect: $0, cornerRadius: 82 * 0.15, style: .circular)
        })
        let corner = pixel(app, width: 100, x: 9, y: 9)
        XCTAssertEqual([corner.r, corner.g, corner.b], [0, 0, 0], "unlit corner is the #000 gap")
        XCTAssertEqual(pixel(app, width: 100, x: 4, y: 50).r, 0, "the gap is #000")
    }

    // MARK: Glow and lens

    /// The outer glow is the lit dot grown by 0.14 of the pitch, with
    /// concentric corners. A square glow would tint its corner pixel.
    func testTheGlowFollowsTheRoundedDot() throws {
        // 3 × 3 at a 100-point pitch; the middle dot is lit, at (109, 109).
        let app = try painted(raster(3, 3, lit: [4]), display(), size: CGSize(width: 300, height: 300), lighting: true)
        let glowCorner = pixel(app, width: 300, x: 95, y: 95)
        XCTAssertEqual([glowCorner.r, glowCorner.g, glowCorner.b], [0, 0, 0],
                       "the glow's corner is the gap, not tinted (\(glowCorner))")
        XCTAssertGreaterThan(pixel(app, width: 300, x: 100, y: 150).r, 0, "the glow's straight edge is tinted")
        XCTAssertGreaterThan(pixel(app, width: 300, x: 150, y: 150).r, 200, "the dot itself is lit")
    }

    /// The lens gradient is clipped to the dot: its corner shows no lens.
    func testTheLensIsClippedToTheRoundedDot() throws {
        let size = CGSize(width: 100, height: 100)
        let lit = try painted(raster(1, 1), display(), size: size, lighting: true)
        let corner = pixel(lit, width: 100, x: 9, y: 9)
        XCTAssertEqual([corner.r, corner.g, corner.b], [0, 0, 0], "an unlit dot's lens stops at its rounded corner")
        XCTAssertGreaterThan(pixel(lit, width: 100, x: 50, y: 12).r, 0x1A, "the lens highlight is on the dot's top edge")
    }

    // MARK: The tiled fill-TV surround

    func testTheSurroundTileDrawsRoundedDots() throws {
        let tile = try XCTUnwrap(MatrixCanvas.offFieldTile(display: display(), pitch: 100, origin: .zero, scale: 1))
        let image = tile.image
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let corner = pixel(data, width: image.width, x: 9, y: 9)
        XCTAssertEqual([corner.r, corner.g, corner.b], [0, 0, 0], "a surround dot's corner is the gap")
        let middle = pixel(data, width: image.width, x: 50, y: 50)
        XCTAssertEqual([middle.r, middle.g, middle.b], [0x1A, 0x1A, 0x1A], "the surround dot is unlit #1A1A1A")
    }

    // MARK: The marquee (#27 review S1)

    /// `MatrixMarqueeLayers` paints its own alpha mask for the dots that the
    /// scrolling colours show through. One 82-point dot (a 100-point pitch,
    /// inset 9) at scale 1: the mask's true corner is the gap, the edge
    /// midpoint is lit. A square marquee dot would light the corner.
    func testTheMarqueeMaskDrawsRoundedDots() throws {
        let size = CGSize(width: 100, height: 100)
        let layout = try XCTUnwrap(MatrixLayout.make(width: 1, height: 1, viewportWidth: 100, viewportHeight: 100,
                                                     presentation: MatrixPresentation()))
        XCTAssertEqual(layout.pitch, 100, accuracy: 1e-9)
        let frame = MatrixTransitionFrame(raster: raster(1, 1, lit: [0]), display: try display(),
                                          presentation: MatrixPresentation(), drift: .zero, lighting: false)
        let backdrop = UIGraphicsImageRenderer(size: size).image { _ in }
        let marquee = MatrixMarqueeLayers()
        marquee.prepare(frame: frame, size: size, scale: 1, layout: layout, backdrop: backdrop)
        let colors = try XCTUnwrap(marquee.layer.sublayers?.first { $0.mask != nil }, "the colours are masked")
        let contents = try XCTUnwrap(colors.mask?.contents, "the mask has contents")
        let mask = contents as! CGImage
        XCTAssertEqual(mask.width, 100)
        var data = [UInt8](repeating: 0, count: mask.width * mask.height * 4)
        let context = try XCTUnwrap(CGContext(data: &data, width: mask.width, height: mask.height, bitsPerComponent: 8,
            bytesPerRow: mask.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(mask, in: CGRect(x: 0, y: 0, width: mask.width, height: mask.height))
        func alpha(_ x: Int, _ y: Int) -> UInt8 { data[(y * mask.width + x) * 4 + 3] }
        XCTAssertEqual(alpha(9, 9), 0, "the marquee dot's true corner is the gap")
        XCTAssertEqual(alpha(90, 90), 0, "every corner is rounded")
        XCTAssertEqual(alpha(50, 9), 255, "the edge midpoint is lit")
        XCTAssertEqual(alpha(9, 50), 255, "the edge midpoint is lit")
        XCTAssertEqual(alpha(4, 50), 0, "the gap is unmasked")
    }
}
