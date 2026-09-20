import XCTest
@testable import FiestaBoardTV

final class BoardGeometryTests: XCTestCase {

    // MARK: Constants agree with the shared spec

    func testPitchMatchesTheSpec() {
        let spec = SpecFixture.spec
        XCTAssertEqual(BoardGeometry.colPitchIn, spec.derived.colPitchIn, accuracy: 1e-9)
        XCTAssertEqual(BoardGeometry.rowPitchIn, spec.derived.rowPitchIn, accuracy: 1e-9)
        XCTAssertEqual(BoardGeometry.blockWidthIn, spec.derived.blockWidthIn, accuracy: 1e-9)
        XCTAssertEqual(BoardGeometry.blockHeightIn, spec.derived.blockHeightIn, accuracy: 1e-9)
    }

    /// Row pitch is derived from the renderer's tile ratios, not measured off
    /// a Note's bezel-heavy height. Asserting the formula here is what stops a
    /// hand-edited literal in board-spec.json from silently winning.
    func testRowPitchFollowsTheTileRatios() {
        let r = SpecFixture.spec.tileRatios
        let colPitchRatio = r.width + r.gutter      // 0.845
        let rowPitchRatio = 1.0 + r.gutter          // 1.145
        XCTAssertEqual(BoardGeometry.rowPitchIn,
                       BoardGeometry.colPitchIn * (rowPitchRatio / colPitchRatio),
                       accuracy: 1e-9)
    }

    // MARK: Spec vectors

    func testScreenDimensionsMatchEverySpecVector() throws {
        for v in SpecFixture.spec.vectors.screenDimensions {
            let (w, h) = try BoardGeometry.screenDimensionsIn(
                diagonal: v.diagonal, aspectW: v.aspectW, aspectH: v.aspectH)
            XCTAssertEqual(w, v.widthIn, accuracy: 1e-6, "width for \(v.diagonal)\"")
            XCTAssertEqual(h, v.heightIn, accuracy: 1e-6, "height for \(v.diagonal)\"")
            XCTAssertEqual(hypot(w, h), v.diagonal, accuracy: 1e-6, "diagonal round-trip")
        }
    }

    func testAutofitMatchesEverySpecVector() throws {
        for v in SpecFixture.spec.vectors.autofit {
            let grid = try BoardGeometry.computeAutofitGrid(
                diagonal: v.diagonal, aspectW: v.aspectW, aspectH: v.aspectH)
            XCTAssertEqual(grid.notesWide, v.notesWide, "notesWide for \(v.name)")
            XCTAssertEqual(grid.notesTall, v.notesTall, "notesTall for \(v.name)")
        }
    }

    func testDefaultAspectIsSixteenNine() throws {
        let a = try BoardGeometry.computeAutofitGrid(diagonal: 65)
        let b = try BoardGeometry.computeAutofitGrid(diagonal: 65, aspectW: 16, aspectH: 9)
        XCTAssertEqual(a.notesWide, b.notesWide)
        XCTAssertEqual(a.notesTall, b.notesTall)
    }

    func testRejectsNonPositiveInputs() {
        XCTAssertThrowsError(try BoardGeometry.screenDimensionsIn(diagonal: 0))
        XCTAssertThrowsError(try BoardGeometry.screenDimensionsIn(diagonal: -5))
        XCTAssertThrowsError(try BoardGeometry.computeAutofitGrid(diagonal: 55, aspectW: 0, aspectH: 9))
        XCTAssertThrowsError(try BoardGeometry.computeAutofitGrid(diagonal: 55, aspectW: 16, aspectH: -1))
    }

    // MARK: autofitScale

    private func input(cols: Int = 30,
                       gridWidthPx: Double = 1000,
                       gridHeightPx: Double = 500,
                       calibration: Double = 1.0) -> AutofitScaleInput {
        AutofitScaleInput(screenWidthPx: 1920, screenHeightPx: 1080,
                          diagonalInches: 65, cols: cols,
                          gridWidthPx: gridWidthPx, gridHeightPx: gridHeightPx,
                          calibration: calibration,
                          colPitchIn: BoardGeometry.colPitchIn)
    }

    /// True scale anchors flap width to the physical column pitch.
    func testAnchorsFlapWidthToColumnPitch() throws {
        let ppi = hypot(1920.0, 1080.0) / 65.0
        let trueScale = (30.0 * BoardGeometry.colPitchIn * ppi) / 1000.0
        // 30 cols at true scale is well under 1920px here, so the stretch
        // clamps at the 10% cap rather than landing on the edge exactly.
        let scale = try BoardGeometry.autofitScale(input())
        XCTAssertEqual(scale, trueScale * BoardGeometry.maxFillStretch, accuracy: 1e-9)
    }

    func testNeverStretchesBeyondTenPercent() throws {
        let scale = try BoardGeometry.autofitScale(input(gridWidthPx: 100, gridHeightPx: 50))
        let ppi = hypot(1920.0, 1080.0) / 65.0
        let trueScale = (30.0 * BoardGeometry.colPitchIn * ppi) / 100.0
        XCTAssertEqual(scale, trueScale * 1.1, accuracy: 1e-9)
    }

    /// The one case that shrinks below true size: a grid that overflows the
    /// screen at true scale (a pocket display) must fit rather than show a
    /// life-size crop of its top-left corner.
    func testShrinksToFitWhenTrueScaleOverflows() throws {
        let overflowing = AutofitScaleInput(
            screenWidthPx: 320, screenHeightPx: 180, diagonalInches: 3,
            cols: 15, gridWidthPx: 400, gridHeightPx: 200,
            calibration: 1.0, colPitchIn: BoardGeometry.colPitchIn)
        let scale = try BoardGeometry.autofitScale(overflowing)
        XCTAssertLessThan(scale * 400, 320.0 + 0.001, "must fit horizontally")
        XCTAssertLessThan(scale * 200, 180.0 + 0.001, "must fit vertically")
    }

    func testCalibrationMultiplies() throws {
        let base = try BoardGeometry.autofitScale(input())
        let nudged = try BoardGeometry.autofitScale(input(calibration: 1.15))
        XCTAssertEqual(nudged, base * 1.15, accuracy: 1e-9)
    }

    func testRejectsUnmeasurableGrid() {
        XCTAssertThrowsError(try BoardGeometry.autofitScale(input(gridWidthPx: 0)))
        XCTAssertThrowsError(try BoardGeometry.autofitScale(input(gridHeightPx: 0)))
        XCTAssertThrowsError(try BoardGeometry.autofitScale(input(cols: 0)))
    }
}
