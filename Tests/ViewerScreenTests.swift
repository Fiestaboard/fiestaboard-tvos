import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardTV

@MainActor
final class ViewerScreenTests: XCTestCase {

    private let screen = CGSize(width: 1920, height: 1080)

    private func snapshot(rows: Int = 12, cols: Int = 30,
                          connection: ConnectionState = .live,
                          dimmed: Bool = false,
                          deleted: Bool = false) -> PanelSnapshot {
        let panel = try! JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        let cells = Array(repeating: Array(repeating: BoardCell.character("A"), count: cols), count: rows)
        return PanelSnapshot(panel: panel, cells: cells, rows: rows, cols: cols,
                             connection: connection, dimmed: dimmed, deleted: deleted)
    }

    /// 8-bit sRGB components of a token colour, for pixel comparisons.
    private func components(of color: Color) -> (r: Int, g: Int, b: Int) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    private func makeApp() -> AppModel {
        AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.viewer.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testLayoutFillsTheScreenInFitMode() throws {
        let model = ViewerModel(app: makeApp(), ref: "1")
        model.snapshot = snapshot()
        model.sizing = .fit
        let layout = try model.layout(for: screen)
        XCTAssertLessThanOrEqual(layout.width, screen.width + 0.001)
        XCTAssertLessThanOrEqual(layout.height, screen.height + 0.001)
        XCTAssertEqual(layout.tiles.count, 12 * 30)
    }

    /// The offer to re-fit must appear only when it would actually help.
    func testGridSuitabilityComparesAspectNotSize() {
        let model = ViewerModel(app: makeApp(), ref: "1")

        // 30x12 note-array on a 16:9 screen: close enough to leave alone.
        model.snapshot = snapshot(rows: 12, cols: 30)
        XCTAssertTrue(model.gridSuitsScreen(screen))

        // 15x21 (a portrait panel) on a landscape TV: badly mismatched.
        model.snapshot = snapshot(rows: 21, cols: 15)
        XCTAssertFalse(model.gridSuitsScreen(screen))
    }

    func testMismatchOfferAppearsOnceForAPortraitPanel() {
        let model = ViewerModel(app: makeApp(), ref: "1")
        model.snapshot = snapshot(rows: 21, cols: 15)
        model.considerResizeOffer(for: screen)
        XCTAssertTrue(model.resizeOfferVisible)

        model.dismissResizeOffer()
        model.considerResizeOffer(for: screen)
        XCTAssertFalse(model.resizeOfferVisible)
    }

    func testNoPanelYetProducesNoLayout() {
        let model = ViewerModel(app: makeApp(), ref: "1")
        model.snapshot = .empty
        XCTAssertThrowsError(try model.layout(for: screen))
    }

    func testOverlayStartsHiddenAndShowsOnDemand() {
        let model = ViewerModel(app: makeApp(), ref: "1")
        XCTAssertFalse(model.overlayVisible)
        model.showOverlay()
        XCTAssertTrue(model.overlayVisible)
    }

    // MARK: Rendering

    func testRendersALiveBoard() {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot()
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
    }

    /// A dropped connection keeps the board and adds only an indicator.
    func testRendersStaleWithTheBoardStillUp() {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot(connection: .stale)
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
    }

    func testRendersTheDeletedPanelState() {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = PanelSnapshot(panel: nil, cells: [], rows: 0, cols: 0,
                                       connection: .live, dimmed: false, deleted: true)
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
    }

    func testMissingBackingBoardHasAnActionableState() throws {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        let json = Fixtures.panelJSON.replacingOccurrences(of: "\"board_missing\":false",
                                                            with: "\"board_missing\":true")
        let panel = try JSONDecoder().decode(Panel.self, from: Data(json.utf8))
        model.snapshot = PanelSnapshot(panel: panel, cells: [], rows: 12, cols: 30,
                                       connection: .live, dimmed: false, deleted: false)
        XCTAssertTrue(model.boardMissing)
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
    }

    func testRendersDimmed() {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot(dimmed: true)
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
    }

    func testViewerMarginsAreTrueBlackForOLED() throws {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot()
        model.sizing = .trueScale
        let image = RenderHarness.image(ViewerScreen(ref: "1", model: model).environment(app))
        let corner = try XCTUnwrap(image.pixel(x: 10, y: 10))
        XCTAssertLessThanOrEqual(Int(corner.r), 2)
        XCTAssertLessThanOrEqual(Int(corner.g), 2)
        XCTAssertLessThanOrEqual(Int(corner.b), 2)
    }

    func testRendersTheOverlay() {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot()
        model.showOverlay()
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
    }

    /// The offer is a message over a live board, so it has to look like one:
    /// a card with its own surface, not text floating on the flaps. Counted
    /// down the middle of the screen rather than asserted at one point, so
    /// the test does not encode the card's exact height.
    func testResizeOfferDrawsACardOverTheBoard() throws {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot(rows: 21, cols: 15)
        model.considerResizeOffer(for: screen)
        XCTAssertTrue(model.resizeOfferVisible)

        let image = RenderHarness.image(ViewerScreen(ref: "1", model: model).environment(app))
        // Taken from the token rather than written out, so retuning the
        // palette does not quietly turn this assertion into a no-op.
        let card = components(of: Fiesta.Colors.surface)
        var surfaceSamples = 0
        for y in stride(from: 200, to: 880, by: 4) {
            guard let sample = image.pixel(x: 960, y: y) else { continue }
            if abs(Int(sample.r) - card.r) <= 3,
               abs(Int(sample.g) - card.g) <= 3,
               abs(Int(sample.b) - card.b) <= 3 {
                surfaceSamples += 1
            }
        }
        XCTAssertGreaterThan(surfaceSamples, 10,
                             "the resize offer should paint a card behind its text")

        // A message on top must not cost the surround its OLED black.
        let corner = try XCTUnwrap(image.pixel(x: 10, y: 10))
        XCTAssertLessThanOrEqual(Int(corner.r), 2)
        XCTAssertLessThanOrEqual(Int(corner.g), 2)
        XCTAssertLessThanOrEqual(Int(corner.b), 2)
    }

    /// The overlay is transient chrome: it belongs at the top, and the board
    /// below it must still be the board.
    func testOverlayStaysAtTheTopOfTheScreen() throws {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot()
        model.showOverlay()

        let image = RenderHarness.image(ViewerScreen(ref: "1", model: model).environment(app))
        // Above the bar is the inset, which stays true black; inside it the
        // material is visibly lighter. An equal pair means nothing drew.
        let aboveBar = try XCTUnwrap(image.pixel(x: 960, y: 20))
        let inBar = try XCTUnwrap(image.pixel(x: 960, y: 110))
        XCTAssertGreaterThan(Int(inBar.r) + Int(inBar.g) + Int(inBar.b),
                             Int(aboveBar.r) + Int(aboveBar.g) + Int(aboveBar.b),
                             "the overlay's bar should be visible against the black inset")
    }

    func testRendersTheLargestGrid() throws {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot(rows: 18, cols: 45)
        let layout = try model.layout(for: screen)
        XCTAssertEqual(layout.tiles.count, 810)
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
    }
}
