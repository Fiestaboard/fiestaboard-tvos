import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class BoardCanvasTests: XCTestCase {

    private func layout(cells: [[BoardCell]], tileHeight: Double = 100) -> BoardLayout {
        BoardLayout.make(rows: cells.count, cols: cells.first?.count ?? 0,
                         cells: cells, tileHeight: tileHeight)
    }

    func testRendersWithoutCrashing() {
        let grid = [[BoardCell.character("A"), .color(.red)], [.blank, .character("9")]]
        RenderHarness.render(BoardCanvas(layout: layout(cells: grid), background: .black))
    }

    /// The largest grid a panel can have — the case the Canvas approach
    /// exists for. 45x18 is an 85" auto-fit board.
    func testRendersTheLargestSupportedGrid() {
        let grid = Array(repeating: Array(repeating: BoardCell.character("W"), count: 45), count: 18)
        RenderHarness.render(BoardCanvas(layout: layout(cells: grid, tileHeight: 55), background: .black))
    }

    func testRendersAnEmptyBoard() {
        RenderHarness.render(BoardCanvas(layout: layout(cells: []), background: .black))
    }

    func testRendersWithAnimationEnabled() {
        let grid = [[BoardCell.character("A")]]
        RenderHarness.render(BoardCanvas(layout: layout(cells: grid), background: .black, animated: true))
    }

    func testFlipTransitionShowsBothFacesAtIntermediateTimes() {
        let started = Date(timeIntervalSince1970: 0)
        let flip = BoardFlipTransition(from: [.character("A")], to: [.character("B")],
                                       columns: 1, startedAt: started)
        let first = flip.sample(index: 0, at: started.addingTimeInterval(0.04))
        XCTAssertEqual(first.cell, .character("A"))
        XCTAssertLessThan(first.scaleY, 1)

        let second = flip.sample(index: 0, at: started.addingTimeInterval(0.14))
        XCTAssertEqual(second.cell, .character("B"))
        XCTAssertLessThan(second.scaleY, 1)

        let settled = flip.sample(index: 0, at: started.addingTimeInterval(0.30))
        XCTAssertEqual(settled.cell, .character("B"))
        XCTAssertEqual(settled.scaleY, 1)
    }

    /// A color tile must paint its pigment across the whole flap. Sampling
    /// the tile centre is what catches a geometry regression that no unit
    /// test on BoardLayout can see.
    func testAColorTilePaintsItsPigment() throws {
        let grid = [[BoardCell.color(.red)]]
        let board = layout(cells: grid, tileHeight: 200)
        let view = BoardCanvas(layout: board, background: .black)
            .frame(width: board.width, height: board.height)

        let image = RenderHarness.image(view, size: CGSize(width: board.width, height: board.height))
        let centre = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: Int(board.height / 2)))

        // #eb4034
        XCTAssertEqual(Int(centre.r), 0xeb, accuracy: 12, "red channel")
        XCTAssertEqual(Int(centre.g), 0x40, accuracy: 12, "green channel")
        XCTAssertEqual(Int(centre.b), 0x34, accuracy: 12, "blue channel")
    }

    func testWhiteHardwareUsesLightFlapsAndInvertsWhiteAndBlackCodes() throws {
        for (cell, shouldBeLight) in [(BoardCell.blank, true),
                                      (.color(.white), false),
                                      (.color(.black), true)] {
            let board = layout(cells: [[cell]], tileHeight: 200)
            let image = RenderHarness.image(BoardCanvas(layout: board, background: .white),
                                            size: CGSize(width: board.width, height: board.height))
            let pixel = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: Int(board.height / 2)))
            if shouldBeLight {
                XCTAssertGreaterThan(Int(pixel.r), 0xc0)
            } else {
                XCTAssertLessThan(Int(pixel.r), 0x60)
            }
        }
    }

    /// The gutter between two tiles must show the board behind them, which
    /// is what proves the pitch is being honoured rather than the tiles
    /// being drawn edge to edge.
    func testTheGutterShowsTheBoardBehind() throws {
        let grid = [[BoardCell.color(.white), BoardCell.color(.white)]]
        let board = layout(cells: grid, tileHeight: 200)
        let view = BoardCanvas(layout: board, background: .black)
            .frame(width: board.width, height: board.height)

        let image = RenderHarness.image(view, size: CGSize(width: board.width, height: board.height))

        // Tile 0 spans 0..140; the gutter runs 140..169; tile 1 starts at 169.
        let gutterX = Int(board.tiles[0].width + board.tileHeight * BoardGeometry.tileGutterRatio / 2)
        let gutter = try XCTUnwrap(image.pixel(x: gutterX, y: Int(board.height / 2)))
        XCTAssertLessThan(Int(gutter.r), 0x60, "the gutter must not be a lit flap")

        let tile = try XCTUnwrap(image.pixel(x: Int(board.tiles[0].width / 2), y: Int(board.height / 2)))
        XCTAssertGreaterThan(Int(tile.r), 0xc0, "a white flap must be lit")
    }

    func testBlackFlapsAndGutterAreTrueBlackForOLED() throws {
        let board = layout(cells: [[.blank, .color(.black)]], tileHeight: 200)
        let image = RenderHarness.image(BoardCanvas(layout: board, background: .black),
                                        size: CGSize(width: board.width, height: board.height))
        let first = try XCTUnwrap(image.pixel(x: Int(board.tiles[0].width / 2), y: 80))
        let gutter = try XCTUnwrap(image.pixel(x: Int(board.tiles[0].width + 10), y: 80))
        let second = try XCTUnwrap(image.pixel(x: Int(board.tiles[1].x + board.tiles[1].width / 2), y: 80))
        for pixel in [first, gutter, second] {
            XCTAssertLessThanOrEqual(Int(pixel.r), 2)
            XCTAssertLessThanOrEqual(Int(pixel.g), 2)
            XCTAssertLessThanOrEqual(Int(pixel.b), 2)
        }
    }

    func testBoardColorsBridgeToSwiftUI() {
        // Guards against a typo silently turning into black.
        XCTAssertNotEqual(BoardColor.red.swiftUI.description, BoardColor.blue.swiftUI.description)
        for color in BoardColor.allCases {
            XCTAssertFalse(color.hex.isEmpty)
        }
    }

    func testTheBoardFontRegistersFromTheBundle() {
        BoardFont.registerIfNeeded()
        XCTAssertNotNil(UIFont(name: BoardFont.familyName, size: 24),
                        "Spline Sans Mono must load from the bundle — the system fallback is a degradation, not the target")
    }
}
