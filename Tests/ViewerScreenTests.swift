import SwiftUI
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

    func testRendersTheOverlay() {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot()
        model.showOverlay()
        RenderHarness.render(ViewerScreen(ref: "1", model: model).environment(app))
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
