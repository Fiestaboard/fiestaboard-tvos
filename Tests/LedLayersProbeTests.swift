import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// A11: the pixel layers against 07b A6 `I166:195024;149:182603`, an
/// instance of `150:7480` "LED pixel canvas 64×36" as redrawn to the DD24 hub
/// model (nodes `280:*`). The fixture's hub panel and frame go through
/// `MatrixRaster.make` and the app's painter, full-bleed at 1920 × 1080 pt,
/// scale 2, lighting on; what Figma draws is the fixture's `figma` block.
/// The tvOS twin of Android G10 (`LedLayersProbeTest`).
@MainActor
final class LedLayersProbeTests: XCTestCase {

    private typealias Fixture = LedViewerSnapshotTests.Fixture

    /// One dot the Figma frame draws: column, row, colour.
    private struct Dot: Hashable { let col: Int, row: Int, rgb: UInt32 }

    private struct Group {
        let node: String
        let layer: Int?
        let rect: [Int]
        let dots: [Dot]
    }

    /// The rendered board's RGBA bytes, 3840 × 2160.
    private struct Render {
        let width: Int, height: Int
        let bytes: [UInt8]

        func rgb(_ x: Int, _ y: Int) -> UInt32 {
            let i = (y * width + x) * 4
            return UInt32(bytes[i]) << 16 | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2])
        }
        /// A dot's centre: (30 · col + 15) pt at scale 2.
        func centre(_ col: Int, _ row: Int) -> UInt32 { rgb((30 * col + 15) * 2, (30 * row + 15) * 2) }
    }

    private static var cachedRender: Render?

    private func fixture() throws -> Fixture { try Fixture.load() }

    private func groups(_ fixture: Fixture) throws -> [Group] {
        let items = try XCTUnwrap(fixture.figma["groups"] as? [[String: Any]])
        return try items.map { item in
            let dots = try XCTUnwrap(item["dots"] as? [[Any]]).map { dot -> Dot in
                let hex = try XCTUnwrap(dot[2] as? String)
                return Dot(col: try XCTUnwrap(dot[0] as? Int), row: try XCTUnwrap(dot[1] as? Int),
                           rgb: try XCTUnwrap(MatrixRaster.hex(hex)))
            }
            return Group(node: try XCTUnwrap(item["node"] as? String), layer: item["layer"] as? Int,
                         rect: try XCTUnwrap(item["rect"] as? [Int]), dots: dots)
        }
    }

    private func render(_ fixture: Fixture) throws -> Render {
        if let cachedRender = Self.cachedRender { return cachedRender }
        let image = try XCTUnwrap(TVSnapshot.image(fixture.board, fullBleed: true).cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let render = Render(width: image.width, height: image.height, bytes: bytes)
        Self.cachedRender = render
        return render
    }

    /// A 1 × 1 opaque canvas layer at (`x`, `y`).
    private func layer(x: Int, y: Int, rgb: UInt32) throws -> CanvasLayer {
        let rgba = Data([UInt8(rgb >> 16 & 255), UInt8(rgb >> 8 & 255), UInt8(rgb & 255), 255]).base64EncodedString()
        let json = try JSONSerialization.data(withJSONObject: ["x": x, "y": y, "width": 1, "height": 1, "rgba": rgba])
        return try JSONDecoder().decode(CanvasLayer.self, from: json)
    }

    // MARK: 1. Structure

    func testThreeLayersInLayersNOrderOnTheFramesGrid() throws {
        let fixture = try fixture()
        let groups = try groups(fixture)
        XCTAssertEqual(fixture.frame.layers.count, 3)
        for group in groups {
            guard let index = group.layer else { continue }
            let layer = fixture.frame.layers[index]
            XCTAssertEqual([layer.x, layer.y, layer.width, layer.height], group.rect,
                           "frame.layers[\(index)] is Figma's layers-\(index) (\(group.node))")
        }
        XCTAssertEqual(groups.compactMap(\.layer), [0, 1, 2], "layers-N groups map to frame.layers[N]")
        let layout = try XCTUnwrap(MatrixLayout.make(width: 64, height: 36, viewportWidth: 1920, viewportHeight: 1080,
                                                     presentation: .init(sizing: .fillTV)))
        XCTAssertEqual(layout.pitch, 30)
        XCTAssertEqual(layout.originX, 0)
        XCTAssertEqual(layout.originY, 0)
        XCTAssertEqual(layout.columns, 0..<64)
        XCTAssertEqual(layout.rows, 0..<36)
        let grid = try XCTUnwrap(fixture.figma["grid"] as? [String: Any])
        XCTAssertEqual(grid["pitchPx"] as? Double, 30)
        XCTAssertEqual(try XCTUnwrap(grid["dotPx"] as? Double), 30 * fixture.panel.matrixDisplay.dotRatio, accuracy: 1e-9)
    }

    // MARK: 2. Z-order: canvases over cells, later layers win

    func testTheFramesStackPutsCellsUnderTheCanvasesInLayerOrder() throws {
        let fixture = try fixture()
        let groups = try groups(fixture)
        let stack = try XCTUnwrap(fixture.figma["zOrderBottomToTop"] as? [String])
        let cells = try XCTUnwrap(groups.first { $0.layer == nil }).node
        let canvases = groups.filter { $0.layer != nil }.sorted { $0.layer! < $1.layer! }.map(\.node)
        let positions = try canvases.map { try XCTUnwrap(stack.firstIndex(of: $0)) }
        XCTAssertLessThan(try XCTUnwrap(stack.firstIndex(of: cells)), positions.min()!, "cells sit under every canvas")
        XCTAssertEqual(positions, positions.sorted(), "canvases stack in layers[] order")
    }

    func testACanvasPaintsOverALitCellAndTheLaterLayerWins() throws {
        let fixture = try fixture()
        let cells = try XCTUnwrap(groups(fixture).first { $0.layer == nil })
        let lit = try XCTUnwrap(cells.dots.first, "a lit cell dot to cover")
        func raster(_ layers: [CanvasLayer]) -> MatrixRaster {
            MatrixRaster.make(panel: fixture.panel, cells: [], richCells: fixture.frame.richCells,
                              layers: fixture.frame.layers + layers)
        }
        let index = lit.row * 64 + lit.col
        XCTAssertEqual(raster([]).pixels[index], lit.rgb, "the cell is lit without the canvas")
        XCTAssertEqual(raster([try layer(x: lit.col, y: lit.row, rgb: 0xFF0000)]).pixels[index], 0xFF0000,
                       "a canvas paints over a lit cell")
        XCTAssertEqual(raster([try layer(x: lit.col, y: lit.row, rgb: 0xFF0000),
                               try layer(x: lit.col, y: lit.row, rgb: 0x0000FF)]).pixels[index], 0x0000FF,
                       "the later layer wins")
    }

    // MARK: 3. Colours

    func testEveryFigmaLitDotHasItsExactColour() throws {
        let fixture = try fixture()
        let raster = fixture.raster
        let render = try render(fixture)
        var checked = 0
        for group in try groups(fixture) {
            for dot in group.dots {
                XCTAssertEqual(raster.pixels[dot.row * 64 + dot.col], dot.rgb,
                               "raster (\(dot.col), \(dot.row)) in \(group.node)")
                XCTAssertEqual(render.centre(dot.col, dot.row), dot.rgb,
                               "rendered centre of (\(dot.col), \(dot.row)) in \(group.node)")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 121 + 361 + 320 + 172)
    }

    func testEveryDotFigmaLeavesDarkIsUnlit() throws {
        let fixture = try fixture()
        let raster = fixture.raster
        let render = try render(fixture)
        let lit = Set(try groups(fixture).flatMap { $0.dots.map { $0.row * 64 + $0.col } })
        var dark = 0
        for index in 0..<(64 * 36) where !lit.contains(index) {
            XCTAssertEqual(raster.pixels[index], 0, "raster (\(index % 64), \(index / 64)) is dark")
            XCTAssertEqual(render.centre(index % 64, index / 64), 0x1A1A1A, "(\(index % 64), \(index / 64)) is unlit #1A1A1A")
            dark += 1
        }
        XCTAssertEqual(dark, 2304 - lit.count)
    }

    // MARK: 4. Transparent pixels

    /// Inside each layer's rect, a pixel with alpha 0 shows what is under it:
    /// the raster is the same there with the layer removed.
    func testTransparentLayerPixelsHideNothing() throws {
        let fixture = try fixture()
        let full = fixture.raster
        var transparent = 0
        for (index, layer) in fixture.frame.layers.enumerated() {
            var others = fixture.frame.layers
            others.remove(at: index)
            let without = MatrixRaster.make(panel: fixture.panel, cells: [], richCells: fixture.frame.richCells, layers: others)
            for y in 0..<layer.height {
                for x in 0..<layer.width where layer.rgba[(y * layer.width + x) * 4 + 3] == 0 {
                    let pixel = (layer.y + y) * 64 + layer.x + x
                    XCTAssertEqual(full.pixels[pixel], without.pixels[pixel],
                                   "layer \(index)'s transparent (\(layer.x + x), \(layer.y + y)) hides nothing")
                    transparent += 1
                }
            }
        }
        XCTAssertGreaterThan(transparent, 0, "the fixture's layers have transparent pixels to check")
    }

    // MARK: 5. Glyphs

    /// The hub's 5×7 text on the hub cell grid, exactly: no offset, no
    /// exceptions. No canvas overlaps the text block.
    func testTheGlyphsAreTheFramesDotsExactly() throws {
        let fixture = try fixture()
        let raster = fixture.raster
        let cells = try XCTUnwrap(groups(fixture).first { $0.layer == nil })
        let rect = cells.rect // x, y, width, height
        var drawn = Set<Dot>()
        for row in rect[1]..<(rect[1] + rect[3]) {
            for col in rect[0]..<(rect[0] + rect[2]) where raster.pixels[row * 64 + col] != 0 {
                drawn.insert(Dot(col: col, row: row, rgb: raster.pixels[row * 64 + col]))
            }
        }
        XCTAssertEqual(drawn, Set(cells.dots), "SUNSET / 6:27 PM, dot for dot")
        XCTAssertEqual(cells.dots.count, 172)
    }

    // MARK: 6. The gap

    /// Between unlit dots, away from any lit dot's glow, the substrate is
    /// OLED black #000 (DD24: a TV app constant).
    func testTheGapBetweenDotsIsBlack() throws {
        let fixture = try fixture()
        let render = try render(fixture)
        // Row 0 and column 63's top rows are unlit: no glow reaches them.
        for col in 0..<63 {
            XCTAssertEqual(render.rgb(30 * (col + 1) * 2, 15 * 2), 0, "vertical gap after column \(col), row 0")
        }
        for col in 0..<64 {
            XCTAssertEqual(render.rgb((30 * col + 15) * 2, 30 * 2), 0, "horizontal gap under row 0, column \(col)")
        }
    }

    // MARK: 7. The true corner

    /// The true corner pixel of a lit water dot (column 0, row 31) is the
    /// gap: the dot is rounded (DD24), so only the glow reaches it. The middle
    /// of the same pixel row is the lit dot, so a blank render can't pass.
    func testTheTrueCornerOfALitDotIsTheGap() throws {
        let fixture = try fixture()
        let render = try render(fixture)
        XCTAssertEqual(fixture.raster.pixels[31 * 64 + 0], 0x2A5F9E, "water at (0, 31)")
        // The dot starts at 2.7 pt = 5.4 px; its first whole pixel is 6.
        let x = 6, y = (30 * 31) * 2 + 6
        let corner = render.rgb(x, y)
        let brightest = max(corner >> 16 & 255, corner >> 8 & 255, corner & 255)
        XCTAssertLessThanOrEqual(brightest, 0x40,
                                 String(format: "the true corner is the gap, not the dot (#%06X)", corner))
        let middle = render.rgb((30 * 0 + 15) * 2, y)
        XCTAssertGreaterThan(max(middle >> 16 & 255, middle >> 8 & 255, middle & 255), 0x60,
                             String(format: "the middle of the same line is the lit dot (#%06X)", middle))
    }
}
