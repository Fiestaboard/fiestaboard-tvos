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

    func testBoardColorsBridgeToSwiftUI() {
        // Guards against a typo silently turning into black.
        XCTAssertNotEqual(BoardColor.red.swiftUI.description, BoardColor.blue.swiftUI.description)
        for color in BoardColor.allCases {
            XCTAssertFalse(color.hex.isEmpty)
        }
    }
}
