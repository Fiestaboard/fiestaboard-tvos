import XCTest
@testable import FiestaBoardTV

/// A5 rules: FiestaUI board metrics, the open-at-launch offer, and the
/// owed focus after a refresh (#21 N4).
@MainActor
final class A5RulesTests: XCTestCase {

    // MARK: Board metrics (FiestaUI `board-metrics.ts`)

    /// FiestaUI rounds each derived dimension to a whole pixel: width
    /// `round(h × 0.70)`, gutter `round(h × 0.145)`; the radius stays exact.
    /// At 07b's 46 px tile that is 32 / 7, a 39 × 53 pitch, and a 29 × 12
    /// board of 1124 × 629: what `149:182628` records.
    func testTileMetricsRoundLikeFiestaUI() {
        let cells = Array(repeating: Array(repeating: BoardCell.blank, count: 29), count: 12)
        let layout = BoardLayout.make(rows: 12, cols: 29, cells: cells, tileHeight: 46)
        XCTAssertEqual(layout.tiles[0].width, 32)
        XCTAssertEqual(layout.tiles[1].x, 39, "column pitch = 32 + 7")
        XCTAssertEqual(layout.tiles[29].y, 53, "row pitch = 46 + 7")
        XCTAssertEqual(layout.tiles[0].radius, 46 * 0.075, accuracy: 1e-9, "radius is paint-only and stays exact")
        XCTAssertEqual(layout.width, 1124)
        XCTAssertEqual(layout.height, 629)
        let size = BoardLayout.size(rows: 12, cols: 29, tileHeight: 46)
        XCTAssertEqual(size.width, 1124)
        XCTAssertEqual(size.height, 629)
    }

    /// Rounding up must never push a fitted board past the screen.
    func testAFittedBoardNeverOverflowsTheScreen() throws {
        let screens = [CGSize(width: 1920, height: 1080), CGSize(width: 768.24, height: 441.54),
                       CGSize(width: 800, height: 450), CGSize(width: 1003, height: 601)]
        for screen in screens {
            for (rows, cols) in [(12, 29), (6, 22), (24, 96), (3, 15), (8, 8)] {
                let cells = Array(repeating: Array(repeating: BoardCell.blank, count: cols), count: rows)
                let layout = try BoardLayout.fitting(rows: rows, cols: cols, cells: cells, in: screen, mode: .fit,
                                                     diagonalInches: 55, calibration: 1, colPitchIn: BoardGeometry.colPitchIn)
                XCTAssertLessThanOrEqual(layout.width, screen.width + 1e-9, "\(cols)×\(rows) in \(screen)")
                XCTAssertLessThanOrEqual(layout.height, screen.height + 1e-9, "\(cols)×\(rows) in \(screen)")
                // …and still fills it, within 5 %: small tiles can only take
                // whole-point pitches (a 96-column board at a ~10 pt tile
                // gets 8, not 8.3), so a little width is given up.
                XCTAssertTrue(layout.width > screen.width * 0.95 || layout.height > screen.height * 0.95,
                              "\(cols)×\(rows) in \(screen) fills the screen (\(layout.width)×\(layout.height))")
            }
        }
    }

    // MARK: The open-at-launch offer (A3 `166:149722`)

    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func signage() -> SignageSettings {
        let suite = "tv.a5.signage.\(UUID().uuidString)"
        suites.append(suite)
        return SignageSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    private func makeApp() async -> AppModel {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.a5.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try? await app.connection.connect(to: URL(string: "http://host:4420")!, displayName: "Maya's FiestaPi")
        return app
    }

    /// `grid` is (rows, cols). 12 × 30 is close to 16:9 once drawn; the
    /// stored screen aspect is the hub's 16:9 default either way.
    private func panel(_ id: String, grid: (Int, Int)? = (12, 30), aspect: (Double, Double) = (16, 9),
                       boardMissing: Bool = false, led: Bool = false) throws -> Panel {
        var json = try JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as! [String: Any]
        json["id"] = id
        json["name"] = "Panel \(id)"
        json["rows"] = grid.map { $0.0 } ?? NSNull()
        json["cols"] = grid.map { $0.1 } ?? NSNull()
        json["screen_aspect_w"] = aspect.0
        json["screen_aspect_h"] = aspect.1
        json["board_missing"] = boardMissing
        if led { json["render_style"] = "led_matrix" }
        return try JSONDecoder().decode(Panel.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func model(_ panels: [Panel], signage: SignageSettings) async -> (PanelsModel, AppModel) {
        let app = await makeApp()
        let model = PanelsModel(app: app, signage: signage)
        model.panels = panels
        return (model, app)
    }

    /// "Fits this TV" is the viewer's own resize-offer rule (the drawn grid
    /// within 25 % of 16:9), so the offer and the viewer never disagree. The
    /// stored screen aspect says nothing: the hub defaults it to 16:9.
    func testAPanelFitsThisTVWhenItsGridIsCloseToSixteenByNine() throws {
        XCTAssertTrue(PanelsModel.fitsThisTV(try panel("a")), "12 × 30")
        XCTAssertTrue(PanelsModel.fitsThisTV(try panel("a", aspect: (4, 3))), "the stored aspect doesn't decide")
        XCTAssertFalse(PanelsModel.fitsThisTV(try panel("a", grid: (6, 22))), "a 22 × 6 flagship is a wide strip")
        XCTAssertFalse(PanelsModel.fitsThisTV(try panel("a", grid: (24, 96))), "a 96 × 24 FiestaPanel")
        XCTAssertFalse(PanelsModel.fitsThisTV(try panel("a", grid: (30, 12))), "a tall board")
        XCTAssertFalse(PanelsModel.fitsThisTV(try panel("a", grid: nil)), "no grid, no claim")
        XCTAssertFalse(PanelsModel.fitsThisTV(try panel("a", boardMissing: true)), "a removed board fits nothing")
        // LED matrices take the same rule, as on Android (G5 `needsResizeOffer`).
        XCTAssertTrue(PanelsModel.fitsThisTV(try panel("a", led: true)))
        XCTAssertFalse(PanelsModel.fitsThisTV(try panel("a", grid: (6, 22), led: true)))
    }

    /// The offer and the viewer's resize offer are one rule.
    func testFitsThisTVIsTheViewersResizeRule() throws {
        for grid in [(12, 30), (6, 22), (24, 96), (9, 16), (20, 30), (30, 12), (3, 15)] {
            let fits = PanelsModel.fitsThisTV(try panel("a", grid: grid))
            XCTAssertEqual(fits, BoardLayout.gridSuits(rows: grid.0, cols: grid.1, noteArray: false,
                                                       screen: CGSize(width: 1920, height: 1080)), "\(grid)")
        }
    }

    func testTheOfferIsTheOnlyPanelThatFits() async throws {
        let only = try panel("only")
        let (model, _) = await model([only, try panel("strip", grid: (6, 22)),
                                      try panel("gone", boardMissing: true)], signage: signage())
        XCTAssertEqual(model.openAtLaunchOffer?.id, "only")
    }

    /// A hub whose only panel doesn't fit: no "fits this TV" claim.
    func testNoOfferForAnOnlyPanelThatDoesNotFit() async throws {
        let (model, _) = await model([try panel("strip", grid: (6, 22))], signage: signage())
        XCTAssertNil(model.openAtLaunchOffer)
    }

    /// One of two panels fits: that one is offered.
    func testTheOneOfTwoThatFitsIsOffered() async throws {
        let (model, _) = await model([try panel("strip", grid: (6, 22)), try panel("wall")], signage: signage())
        XCTAssertEqual(model.openAtLaunchOffer?.id, "wall")
    }

    func testNoOfferWhenNoneOrSeveralFit() async throws {
        let (none, _) = await model([try panel("square", grid: (24, 96))], signage: signage())
        XCTAssertNil(none.openAtLaunchOffer)
        let (two, _) = await model([try panel("a"), try panel("b")], signage: signage())
        XCTAssertNil(two.openAtLaunchOffer)
        let (empty, _) = await model([], signage: signage())
        XCTAssertNil(empty.openAtLaunchOffer)
    }

    func testNoOfferOnceAPanelOpensAtLaunch() async throws {
        let (model, app) = await model([try panel("only")], signage: signage())
        app.connection.setDefaultPanel(ref: "only")
        XCTAssertNil(model.openAtLaunchOffer)
    }

    func testAlwaysOpenSetsThePanelAndIsNotOfferedAgain() async throws {
        let settings = signage()
        let (model, app) = await model([try panel("only")], signage: settings)
        model.acceptOpenAtLaunch()
        XCTAssertEqual(app.connection.saved?.defaultPanelRef, "only")
        XCTAssertTrue(settings.openAtLaunchOffered)
        XCTAssertNil(model.openAtLaunchOffer)
    }

    func testNotNowIsRememberedAndChangesNothing() async throws {
        let settings = signage()
        let (model, app) = await model([try panel("only")], signage: settings)
        model.dismissOpenAtLaunch()
        XCTAssertNil(app.connection.saved?.defaultPanelRef)
        XCTAssertTrue(settings.openAtLaunchOffered)
        XCTAssertNil(model.openAtLaunchOffer)
        // A fresh model on the same device: still not offered.
        let (again, _) = await self.model([try panel("only")], signage: settings)
        XCTAssertNil(again.openAtLaunchOffer)
    }

    func testTheOfferedFlagPersists() {
        let suite = "tv.a5.persist.\(UUID().uuidString)"
        suites.append(suite)
        XCTAssertFalse(SignageSettings(defaults: UserDefaults(suiteName: suite)!).openAtLaunchOffered)
        SignageSettings(defaults: UserDefaults(suiteName: suite)!).openAtLaunchOffered = true
        XCTAssertTrue(SignageSettings(defaults: UserDefaults(suiteName: suite)!).openAtLaunchOffered)
    }

    /// The copy is 07b's, with the panel's and the hub's names.
    func testTheOfferCopyIsA3s() {
        XCTAssertEqual(TVCopy.Panels.openAtLaunchTitle(panel: "Living room TV"), "Always open Living room TV?")
        XCTAssertEqual(TVCopy.Panels.openAtLaunchBody(hub: "Maya’s FiestaPi"),
                       "It’s the only panel on Maya’s FiestaPi that fits this TV. Open it straight away whenever "
                       + "the app starts. You can change this in Settings › This Apple TV.")
        XCTAssertEqual(TVCopy.Panels.openAtLaunchAccept, "Always open")
        XCTAssertEqual(TVCopy.Panels.openAtLaunchDismiss, "Not now")
    }

    // MARK: Owed focus after a refresh (#21 N4)

    func testOwedFocusIsGivenBackOnceBeforeItExpires() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        var owed = OwedFocus()
        owed.owe("p", at: start)
        XCTAssertNil(owed.take(landedOn: nil, at: start.addingTimeInterval(0.1)), "focus passing through nothing keeps the debt")
        XCTAssertEqual(owed.take(landedOn: "q", at: start.addingTimeInterval(0.3)), "p")
        XCTAssertNil(owed.take(landedOn: "r", at: start.addingTimeInterval(0.4)), "one-shot")
    }

    func testOwedFocusExpires() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        var owed = OwedFocus()
        owed.owe("p", at: start)
        XCTAssertNil(owed.take(landedOn: "q", at: start.addingTimeInterval(OwedFocus.expiry + 0.01)),
                     "a later press must never be pulled back to the refreshed card")
        XCTAssertNil(owed.take(landedOn: "q", at: start.addingTimeInterval(0.1)), "and the debt is gone")
    }

    func testOwedFocusOnTheSameCardIsSettled() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        var owed = OwedFocus()
        owed.owe("p", at: start)
        XCTAssertNil(owed.take(landedOn: "p", at: start.addingTimeInterval(0.2)))
        XCTAssertNil(owed.take(landedOn: "q", at: start.addingTimeInterval(0.3)), "settled, not owed again")
    }
}
