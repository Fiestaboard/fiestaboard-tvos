import Observation
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
                          deleted: Bool = false,
                          drift: BoardOffset = .zero) -> PanelSnapshot {
        let panel = try! JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        let cells = Array(repeating: Array(repeating: BoardCell.character("A"), count: cols), count: rows)
        return PanelSnapshot(panel: panel, cells: cells, rows: rows, cols: cols,
                             connection: connection, dimmed: dimmed, deleted: deleted,
                             drift: drift)
    }

    /// 8-bit sRGB components of a token colour, for pixel comparisons.
    private func components(of color: Color) -> (r: Int, g: Int, b: Int) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// Assert one sample is the viewer's surround: true black, and *painted*.
    ///
    /// The alpha is the load-bearing half, and dropping it turns every
    /// surround assertion in this file into a no-op. `RenderHarness.image`
    /// hosts on a `.clear` background with `format.opaque = false`, and
    /// `UIImage.pixel` reads through a premultiplied context — so a pixel
    /// nothing ever painted comes back (0, 0, 0, 0) and satisfies any test of
    /// r/g/b alone. That is docs/HANDOFF.md hazard 2 in the one place it is
    /// hardest to spot.
    ///
    /// Alpha is also the only channel that separates the two ways the ground
    /// goes wrong, because neither of them changes its colour. Move
    /// `.opacity(0.35)` back onto the outer `ZStack` and the ground dims with
    /// the board: 35% black over nothing is (0, 0, 0, 89) at *every* sample,
    /// so this helper catches that one wherever it is called. Move `.offset`
    /// back and the ground slides out from under two edges, leaving
    /// (0, 0, 0, 0) — but only inside a band as wide as the drift, so that
    /// one is caught by *where* the caller samples and not by this helper.
    /// `testDriftAndDimLeaveTheSurroundTrueBlack` is the caller that places a
    /// sample there; the rest assert the OLED contract, not the slide.
    private func assertSurroundIsTrueBlack(_ image: UIImage, x: Int, y: Int,
                                           file: StaticString = #filePath,
                                           line: UInt = #line) throws {
        let pixel = try XCTUnwrap(image.pixel(x: x, y: y), "no pixel at (\(x), \(y))",
                                  file: file, line: line)
        XCTAssertGreaterThanOrEqual(Int(pixel.a), 250,
                                    "(\(x), \(y)) is not an opaque pixel: either nothing "
                                    + "painted the surround or the dim reached it",
                                    file: file, line: line)
        XCTAssertLessThanOrEqual(Int(pixel.r), 2, "(\(x), \(y)) red", file: file, line: line)
        XCTAssertLessThanOrEqual(Int(pixel.g), 2, "(\(x), \(y)) green", file: file, line: line)
        XCTAssertLessThanOrEqual(Int(pixel.b), 2, "(\(x), \(y)) blue", file: file, line: line)
    }

    private func makeApp(defaultPanelRef: String? = nil) -> AppModel {
        let defaults = UserDefaults(suiteName: "tv.viewer.\(UUID().uuidString)")!
        if defaultPanelRef != nil {
            // Written the way a paired TV has it on disk. The key is spelled
            // out because `ConnectionStore` keeps it private, and going in
            // through `connect()` would need a stubbed handshake to say
            // nothing more than "this TV opens into that panel".
            let saved = SavedConnection(host: URL(string: "http://host:4420")!,
                                        displayName: "Board",
                                        defaultPanelRef: defaultPanelRef)
            defaults.set(try! JSONEncoder().encode(saved), forKey: "fiestaboard.connection")
        }
        return AppModel(connection: ConnectionStore(
            defaults: defaults,
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

    func testResizeOfferKeepsViewerControlsHiddenUntilDismissed() {
        let model = ViewerModel(app: makeApp(), ref: "1")
        model.snapshot = snapshot(rows: 21, cols: 15)
        model.considerResizeOffer(for: screen)
        XCTAssertTrue(model.resizeOfferVisible)

        model.showOverlay()
        XCTAssertFalse(model.overlayVisible, "Navigating the resize prompt must not introduce competing controls")
        model.dismissResizeOffer()
        model.showOverlay()
        XCTAssertTrue(model.overlayVisible, "Normal viewer controls must work after Later")
    }

    func testResizeOfferReplacesControlsShownWhileLoading() {
        let model = ViewerModel(app: makeApp(), ref: "1")
        model.showOverlay()
        XCTAssertTrue(model.overlayVisible)
        model.snapshot = snapshot(rows: 21, cols: 15)
        model.considerResizeOffer(for: screen)
        XCTAssertTrue(model.resizeOfferVisible)
        XCTAssertFalse(model.overlayVisible, "A newly opened resize prompt must remove already visible controls")
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
        try assertSurroundIsTrueBlack(image, x: 10, y: 10)
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
    /// through empty top padding: the material must obscure the live board
    /// there, while leaving board detail outside the card visible.
    func testResizeOfferDrawsACardOverTheBoard() throws {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot(rows: 21, cols: 15)
        model.sizing = .fit
        model.considerResizeOffer(for: screen)
        XCTAssertTrue(model.resizeOfferVisible)

        let image = RenderHarness.image(ViewerScreen(ref: "1", model: model).environment(app))
        let capture = XCTAttachment(image: image)
        capture.name = "Resize offer — actual render"
        capture.lifetime = .keepAlways
        add(capture)
        // The same app has already offered this ref, so a fresh viewer can
        // render the unobscured board without triggering another offer.
        let referenceModel = ViewerModel(app: app, ref: "1")
        referenceModel.snapshot = snapshot(rows: 21, cols: 15)
        referenceModel.sizing = .fit
        let reference = RenderHarness.image(ViewerScreen(ref: "1", model: referenceModel).environment(app))
        XCTAssertFalse(referenceModel.resizeOfferVisible)
        let baseline = XCTAttachment(image: reference)
        baseline.name = "Resize offer — unobscured board reference"
        baseline.lifetime = .keepAlways
        add(baseline)

        // Material over black can itself be black; its meaningful contract
        // is obscuring the busy backdrop. The strip at y300–332 is inside
        // the card's top padding, above its first text line. Compare actual
        // glyph pixels with a reference so a missing board cannot pass.
        var obscuredGlyphSamples = 0
        var preservedGlyphSamples = 0
        for y in stride(from: 100, through: 332, by: 4) {
            guard y <= 220 || y >= 300 else { continue }
            for x in stride(from: 680, through: 1240, by: 4) {
                let original = try XCTUnwrap(reference.pixel(x: x, y: y))
                guard original.r > 100 else { continue }
                let rendered = try XCTUnwrap(image.pixel(x: x, y: y))
                if y >= 300, rendered.a >= 250, Int(rendered.r) < Int(original.r) / 2 {
                    obscuredGlyphSamples += 1
                } else if y <= 220, abs(Int(rendered.r) - Int(original.r)) < 20 {
                    preservedGlyphSamples += 1
                }
            }
        }
        XCTAssertGreaterThan(obscuredGlyphSamples, 10,
                             "the resize offer's material must obscure board detail behind its empty padding")
        XCTAssertGreaterThan(preservedGlyphSamples, 10,
                             "the live board must remain visible outside the card")

        // A message on top must not cost the surround its OLED black.
        try assertSurroundIsTrueBlack(image, x: 10, y: 10)
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

    /// The dim and the drift wrap the board alone. Applied to the whole stack
    /// they slid the true-black ground aside and uncovered a band of the app
    /// ground along two edges — on the one screen contracted to be black.
    ///
    /// The two regressions do not show in the same places, so the samples are
    /// picked to separate them. The dim reaches the whole ground, so any of
    /// the four corners catches it. The slide is only as wide as the drift —
    /// 8 points, moving the ground down and right — so it shows only where
    /// x < 8 along the left edge and y < 8 along the top. The four corners
    /// sit 10 points in, outside that band, so they never caught the slide at
    /// all in the round they were documented as catching it. The last two
    /// samples are inside it, one per axis, and derived from the amplitude so
    /// retuning it cannot quietly move them back out.
    ///
    /// There is no companion test for a `.unauthorized` render: the viewer has
    /// no chrome for that state, because `apply` routes away in the same
    /// update that sets it. The test that used to be here reached the state by
    /// assigning `snapshot` directly, which is a thing only a test can do.
    func testDriftAndDimLeaveTheSurroundTrueBlack() throws {
        let app = makeApp()
        let model = ViewerModel(app: app, ref: "1")
        model.snapshot = snapshot(dimmed: true,
                                  drift: BoardOffset(x: BoardDrift.defaultAmplitude,
                                                     y: BoardDrift.defaultAmplitude))
        model.sizing = .trueScale

        let image = RenderHarness.image(ViewerScreen(ref: "1", model: model).environment(app))
        let inBand = Int(BoardDrift.defaultAmplitude / 2)
        for point in [(10, 10), (1910, 10), (10, 1070), (1910, 1070),
                      (inBand, 540), (960, inBand)] {
            try assertSurroundIsTrueBlack(image, x: point.0, y: point.1)
        }
    }

    // MARK: Rebinding

    /// `.viewer(a)` and `.viewer(b)` are one branch of RootView's switch, so
    /// the screen and its `@State` model survive the change. Without an
    /// explicit teardown every Top Shelf jump opened the panel already up.
    func testChangingTheRefRebindsTheModelToTheNewPanel() {
        let app = makeApp()
        let box = ViewerRefBox(ref: "a")
        let log = ViewerModelLog()
        let view = ViewerRefSwitcher(box: box, onModel: { log.refs.append($0.ref) })
            .environment(app)

        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: RenderHarness.tvSize)
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        box.ref = "b"
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.isHidden = true
        window.rootViewController = nil

        XCTAssertEqual(log.refs.last, "b",
                       "the viewer must rebuild its model when the route's ref changes")
    }

    // MARK: A panel that stops existing

    func testADeletedDefaultPanelStopsBeingTheDefault() {
        let app = makeApp(defaultPanelRef: "1")
        XCTAssertEqual(app.connection.saved?.defaultPanelRef, "1")

        let model = ViewerModel(app: app, ref: "1")
        model.apply(snapshot(deleted: true))

        XCTAssertNil(app.connection.saved?.defaultPanelRef,
                     "a panel deleted on the server must not be what this TV boots into")
        XCTAssertTrue(model.snapshot.deleted, "and the explanation still shows, once")
    }

    func testADeletedPanelThatIsNotTheDefaultLeavesTheDefaultAlone() {
        let app = makeApp(defaultPanelRef: "1")
        let model = ViewerModel(app: app, ref: "2")
        model.apply(snapshot(deleted: true))
        XCTAssertEqual(app.connection.saved?.defaultPanelRef, "1")
    }

    func testARefusedSessionSendsTheViewerToSignIn() {
        let app = makeApp()
        app.route = .viewer("1")
        let model = ViewerModel(app: app, ref: "1")
        model.apply(snapshot(connection: .unauthorized))
        XCTAssertEqual(app.route, .signIn)
    }

    // MARK: Overlay lifetime

    func testTheOverlayTimeoutIsLongerUnderVoiceOver() {
        let app = makeApp()
        XCTAssertEqual(ViewerModel(app: app, ref: "1", isVoiceOverRunning: { false }).overlayTimeout,
                       ViewerModel.overlayTimeout)
        XCTAssertEqual(ViewerModel(app: app, ref: "1", isVoiceOverRunning: { true }).overlayTimeout,
                       ViewerModel.overlayTimeoutVoiceOver)
        XCTAssertGreaterThan(ViewerModel.overlayTimeoutVoiceOver, ViewerModel.overlayTimeout)
    }

    /// Keeping the bar alive is a report of interaction, not a way to summon
    /// it: a focus change arriving after it has gone must not bring it back.
    func testKeepingTheOverlayAliveOnlyAppliesWhileItIsUp() {
        let model = ViewerModel(app: makeApp(), ref: "1")
        model.keepOverlayAlive()
        XCTAssertFalse(model.overlayVisible)

        model.showOverlay()
        model.keepOverlayAlive()
        XCTAssertTrue(model.overlayVisible)

        model.hideOverlay()
        XCTAssertFalse(model.overlayVisible)
    }

    func testStoppingTheViewerTakesItsChromeWithIt() {
        let model = ViewerModel(app: makeApp(), ref: "1")
        model.showOverlay()
        model.stop()
        XCTAssertFalse(model.overlayVisible)
    }
}

// MARK: - Harness for the rebinding test
//
// `ViewerScreen` owns its model, so the only way to see which panel the model
// it built is bound to is to be handed it. `onModel` is that seam; these three
// types are what drive it through a real SwiftUI update.

@Observable
private final class ViewerRefBox {
    var ref: String
    init(ref: String) { self.ref = ref }
}

private final class ViewerModelLog {
    var refs: [String] = []
}

private struct ViewerRefSwitcher: View {
    let box: ViewerRefBox
    let onModel: (ViewerModel) -> Void

    var body: some View {
        ViewerScreen(ref: box.ref, onModel: onModel)
    }
}
