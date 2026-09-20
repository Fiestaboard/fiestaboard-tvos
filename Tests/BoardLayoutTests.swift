import XCTest
@testable import FiestaBoardTV

final class BoardLayoutTests: XCTestCase {

    private func cells(rows: Int, cols: Int, code: Int = 1) -> [[BoardCell]] {
        Array(repeating: Array(repeating: BoardTables.cell(forCode: code, code62: .degree), count: cols),
              count: rows)
    }

    func testTileCountMatchesTheGrid() {
        let layout = BoardLayout.make(rows: 6, cols: 22, cells: cells(rows: 6, cols: 22), tileHeight: 20)
        XCTAssertEqual(layout.tiles.count, 132)
    }

    /// Tile geometry is the whole fidelity story: width 0.70·h, gutter
    /// 0.145·h on both axes, radius 0.075·h.
    func testTileDimensionsFollowTheRatios() {
        let layout = BoardLayout.make(rows: 1, cols: 1, cells: cells(rows: 1, cols: 1), tileHeight: 100)
        let tile = layout.tiles[0]
        XCTAssertEqual(tile.height, 100, accuracy: 1e-9)
        XCTAssertEqual(tile.width, 70, accuracy: 1e-9)
        XCTAssertEqual(tile.radius, 7.5, accuracy: 1e-9)
    }

    func testTilesArePitchedByWidthPlusGutter() {
        let layout = BoardLayout.make(rows: 2, cols: 2, cells: cells(rows: 2, cols: 2), tileHeight: 100)
        let colPitch = 70.0 + 14.5
        let rowPitch = 100.0 + 14.5
        XCTAssertEqual(layout.tiles[0].x, 0, accuracy: 1e-9)
        XCTAssertEqual(layout.tiles[1].x, colPitch, accuracy: 1e-9)
        XCTAssertEqual(layout.tiles[0].y, 0, accuracy: 1e-9)
        XCTAssertEqual(layout.tiles[2].y, rowPitch, accuracy: 1e-9)
    }

    /// The grid is borderless: no outer gutter, so the board can run to the
    /// screen edge the way the web viewer does.
    func testOverallSizeExcludesTheOuterGutter() {
        let layout = BoardLayout.make(rows: 3, cols: 15, cells: cells(rows: 3, cols: 15), tileHeight: 100)
        XCTAssertEqual(layout.width, 15 * 84.5 - 14.5, accuracy: 1e-9)
        XCTAssertEqual(layout.height, 3 * 114.5 - 14.5, accuracy: 1e-9)
    }

    func testTilesCarryTheirCellAndCoordinates() {
        var grid = cells(rows: 2, cols: 2)
        grid[1][0] = .color(.red)
        let layout = BoardLayout.make(rows: 2, cols: 2, cells: grid, tileHeight: 10)
        let tile = layout.tiles.first { $0.row == 1 && $0.col == 0 }
        XCTAssertEqual(tile?.cell, .color(.red))
    }

    /// A frame whose shape disagrees with the panel config must not crash —
    /// a reshape in flight is a normal, transient state.
    func testRaggedOrShortFramesPadWithBlanks() {
        let ragged: [[BoardCell]] = [[.character("A")]]
        let layout = BoardLayout.make(rows: 2, cols: 3, cells: ragged, tileHeight: 10)
        XCTAssertEqual(layout.tiles.count, 6)
        XCTAssertEqual(layout.tiles.first { $0.row == 0 && $0.col == 0 }?.cell, .character("A"))
        XCTAssertEqual(layout.tiles.first { $0.row == 0 && $0.col == 2 }?.cell, .blank)
        XCTAssertEqual(layout.tiles.first { $0.row == 1 && $0.col == 0 }?.cell, .blank)
    }

    func testOversizedFramesAreCroppedNotCrashed() {
        let layout = BoardLayout.make(rows: 1, cols: 1, cells: cells(rows: 4, cols: 4), tileHeight: 10)
        XCTAssertEqual(layout.tiles.count, 1)
    }

    func testEmptyGridsProduceNoTiles() {
        let layout = BoardLayout.make(rows: 0, cols: 0, cells: [], tileHeight: 10)
        XCTAssertTrue(layout.tiles.isEmpty)
        XCTAssertEqual(layout.width, 0)
    }

    // MARK: Fitting to a screen

    func testFitModeFillsTheScreenWithoutOverflowing() throws {
        let screen = CGSize(width: 1920, height: 1080)
        let layout = try BoardLayout.fitting(rows: 12, cols: 30, cells: cells(rows: 12, cols: 30),
                                             in: screen, mode: .fit,
                                             diagonalInches: 65, calibration: 1.0,
                                             colPitchIn: BoardGeometry.colPitchIn)
        XCTAssertLessThanOrEqual(layout.width, 1920.001)
        XCTAssertLessThanOrEqual(layout.height, 1080.001)
        // It must actually fill one axis, not sit small in the middle.
        let fillsWidth = abs(layout.width - 1920) < 1
        let fillsHeight = abs(layout.height - 1080) < 1
        XCTAssertTrue(fillsWidth || fillsHeight, "fit must touch one axis")
    }

    func testFitModePreservesAspect() throws {
        let unscaled = BoardLayout.make(rows: 12, cols: 30, cells: cells(rows: 12, cols: 30), tileHeight: 100)
        let fitted = try BoardLayout.fitting(rows: 12, cols: 30, cells: cells(rows: 12, cols: 30),
                                             in: CGSize(width: 1920, height: 1080), mode: .fit,
                                             diagonalInches: 65, calibration: 1.0,
                                             colPitchIn: BoardGeometry.colPitchIn)
        XCTAssertEqual(fitted.width / fitted.height,
                       unscaled.width / unscaled.height, accuracy: 1e-6)
    }

    /// True scale is allowed to leave margins — that is the point of it.
    func testTrueScaleMatchesTheGeometryHelper() throws {
        let rows = 12, cols = 30
        let base = BoardLayout.make(rows: rows, cols: cols, cells: cells(rows: rows, cols: cols), tileHeight: 100)
        let expected = try BoardGeometry.autofitScale(
            AutofitScaleInput(screenWidthPx: 1920, screenHeightPx: 1080, diagonalInches: 65,
                              cols: cols, gridWidthPx: base.width, gridHeightPx: base.height,
                              calibration: 1.0, colPitchIn: BoardGeometry.colPitchIn))
        let layout = try BoardLayout.fitting(rows: rows, cols: cols, cells: cells(rows: rows, cols: cols),
                                             in: CGSize(width: 1920, height: 1080), mode: .trueScale,
                                             diagonalInches: 65, calibration: 1.0,
                                             colPitchIn: BoardGeometry.colPitchIn)
        XCTAssertEqual(layout.width, base.width * expected, accuracy: 1e-6)
    }

    /// Font size is a fixed fraction of tile height so glyphs scale with the
    /// board instead of being chosen per screen.
    func testFontSizeTracksTileHeight() {
        let small = BoardLayout.make(rows: 1, cols: 1, cells: cells(rows: 1, cols: 1), tileHeight: 20)
        let large = BoardLayout.make(rows: 1, cols: 1, cells: cells(rows: 1, cols: 1), tileHeight: 40)
        XCTAssertEqual(large.fontSize, small.fontSize * 2, accuracy: 1e-9)
        XCTAssertGreaterThan(small.fontSize, 0)
    }

    func testZeroSizedScreensAreRejected() {
        XCTAssertThrowsError(try BoardLayout.fitting(rows: 1, cols: 1, cells: cells(rows: 1, cols: 1),
                                                     in: .zero, mode: .fit, diagonalInches: 65,
                                                     calibration: 1.0, colPitchIn: BoardGeometry.colPitchIn))
    }
}
