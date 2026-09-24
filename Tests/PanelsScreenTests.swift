import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class PanelsScreenTests: XCTestCase {

    private func makeApp() async -> AppModel {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.panels.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try? await app.connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        return app
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testLoadsThePanelList() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        XCTAssertEqual(model.panels.count, 1)
        XCTAssertEqual(model.panels.first?.name, "Living Room")
        XCTAssertNil(model.errorMessage)
    }

    /// An instance with auth on that we cannot satisfy must offer sign-in,
    /// not a dead-end error.
    func testA401RoutesToSignIn() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(#"{"detail":"Not authenticated"}"#, status: 401), for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        XCTAssertEqual(app.route, .signIn)
    }

    func testAnUnreachableBoardShowsAnError() async {
        let app = await makeApp()
        let model = PanelsModel(app: app)
        await model.load()   // nothing enqueued
        XCTAssertNotNil(model.errorMessage)
    }

    /// A board that answers promptly with a lockout, a server fault, or a
    /// payload this app cannot parse is NOT an unreachable board. Saying so
    /// sends people to check cables while the board sits there replying.
    func testALockoutSaysSoRatherThanBlamingTheNetwork() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(
            .json(#"{"detail":"Too many failed login attempts. Try again later."}"#, status: 429),
            for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        let message = model.errorMessage ?? ""
        XCTAssertFalse(message.contains("still on"),
                       "a 429 is not an unreachable board, got: \(message)")
        XCTAssertTrue(message.lowercased().contains("too many")
                      || message.lowercased().contains("sign-in"),
                      "a 429 should explain the lockout, got: \(message)")
    }

    func testAServerFaultReportsItsStatus() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(#"{"detail":"boom"}"#, status: 500), for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        let message = model.errorMessage ?? ""
        XCTAssertTrue(message.contains("500"), "the status is the whole clue, got: \(message)")
        XCTAssertFalse(message.contains("still on"))
    }

    func testAnUnparseablePayloadSaysSoRatherThanBlamingTheNetwork() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(#"{"panels":[{"id":"1"}]}"#), for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        let message = model.errorMessage ?? ""
        XCTAssertFalse(message.contains("still on"),
                       "a board that replied is reachable, got: \(message)")
        XCTAssertTrue(message.lowercased().contains("understand")
                      || message.lowercased().contains("version"),
                      "a decode failure should point at versions, got: \(message)")
    }

    /// The one case that really is the network keeps its plain wording.
    func testAnUnreachableBoardStillSaysCheckItIsOn() async {
        let app = await makeApp()
        let model = PanelsModel(app: app)
        await model.load()   // nothing enqueued -> transport failure
        XCTAssertTrue((model.errorMessage ?? "").contains("still on"))
    }

    func testAnEmptyListIsNotAnError() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(#"{"panels":[],"total":0}"#), for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        XCTAssertTrue(model.panels.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testPanelDescribesItsGridAndScreen() throws {
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        XCTAssertEqual(panel.gridDescription, "30 × 12")
        XCTAssertTrue(panel.screenDescription.contains("65"))
    }

    /// An orphaned panel must say so rather than offering a board that
    /// cannot render.
    func testAPanelWithAMissingBoardDescribesItself() throws {
        let orphan = Fixtures.panelJSON
            .replacingOccurrences(of: "\"board_missing\":false", with: "\"board_missing\":true")
            .replacingOccurrences(of: "\"rows\":12", with: "\"rows\":null")
            .replacingOccurrences(of: "\"cols\":30", with: "\"cols\":null")
        let panel = try JSONDecoder().decode(Panel.self, from: Data(orphan.utf8))
        XCTAssertTrue(panel.boardMissing)
        XCTAssertEqual(panel.gridDescription, "No board")
    }

    func testScreenRendersLoadedEmptyAndErrorStates() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        RenderHarness.render(PanelsScreen().environment(app))
    }
}

// MARK: - Board previews on the cards

extension PanelsScreenTests {

    /// `n` panels with distinct ids, from the one-panel fixture.
    private func panelsList(count: Int, boardMissing: Bool = false) -> String {
        let panels = (0..<count).map { index -> String in
            var json = Fixtures.panelJSON
                .replacingOccurrences(of: "\"id\":\"abc123def456\"",
                                      with: "\"id\":\"panel-\(index)\"")
                .replacingOccurrences(of: "\"name\":\"Living Room\"",
                                      with: "\"name\":\"Panel \(index)\"")
            if boardMissing {
                json = json.replacingOccurrences(of: "\"board_missing\":false",
                                                 with: "\"board_missing\":true")
            }
            return json
        }
        return "{\"panels\":[\(panels.joined(separator: ","))],\"total\":\(count)}"
    }

    /// Previews arrive after the list, so a test has to let them land.
    private func settledPreview(_ model: PanelsModel, for panel: Panel) async -> PanelPreviewState {
        for _ in 0..<300 {
            let state = model.previewState(for: panel)
            if state != .loading { return state }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return model.previewState(for: panel)
    }

    /// The point of the card: it shows what the board currently says.
    func testEachPanelGetsItsCurrentFrameAsAPreview() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        let model = PanelsModel(app: app)
        await model.load()

        let panel = try! XCTUnwrap(model.panels.first)
        guard case .ready(let preview) = await settledPreview(model, for: panel) else {
            return XCTFail("expected a preview, got \(model.previewState(for: panel))")
        }
        XCTAssertEqual(preview.rows, 2)
        XCTAssertEqual(preview.cols, 3)
        XCTAssertEqual(preview.message, "HI")
        XCTAssertEqual(preview.cells.first?.first, .character("H"))
    }

    /// The list must not wait on the pictures.
    func testThePanelListIsReadyBeforeAnyPreviewIs() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        let model = PanelsModel(app: app)
        await model.load()
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.panels.count, 1)
        XCTAssertEqual(model.previewState(for: model.panels[0]), .loading)
    }

    /// One board refusing one frame is not the screen failing.
    func testAFrameFailureLeavesTheCardAndNoError() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        // Nothing enqueued for /frame.
        let model = PanelsModel(app: app)
        await model.load()

        let panel = try! XCTUnwrap(model.panels.first)
        let state = await settledPreview(model, for: panel)
        XCTAssertEqual(state, .unavailable)
        XCTAssertEqual(model.panels.count, 1)
        XCTAssertNil(model.errorMessage)
    }

    /// More panels than the concurrency limit: every one still gets a turn.
    func testEveryPanelIsFetchedEvenBeyondTheConcurrencyLimit() async {
        let count = PanelsModel.previewConcurrency + 3
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(panelsList(count: count)), for: "/api/panels")
        // Twice over: `load()` starts a round of its own, and this test then
        // drives a second one it can actually await.
        for _ in 0..<(count * 2) { StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame") }
        let model = PanelsModel(app: app)
        await model.load()
        await model.refreshPreviews(for: model.panels)

        XCTAssertEqual(model.panels.count, count)
        for panel in model.panels {
            guard case .ready = model.previewState(for: panel) else {
                return XCTFail("\(panel.id) never got a preview")
            }
        }
    }

    /// A panel with no board has no frame to ask for, and asking would only
    /// spend a round trip on a 404.
    func testAPanelWithNoBoardIsNeverAskedForAFrame() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(panelsList(count: 1, boardMissing: true)), for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        await model.refreshPreviews(for: model.panels)

        XCTAssertEqual(model.panels.count, 1)
        XCTAssertTrue(model.panels[0].boardMissing)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url.path.contains("/frame") },
                       "a boardless panel must not be asked for a frame")
    }

    /// A preview already on screen stays there while its replacement is
    /// fetched: coming back from the viewer must not blank the grid.
    func testAnExistingPreviewSurvivesAReload() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        let model = PanelsModel(app: app)
        await model.load()
        let panel = try! XCTUnwrap(model.panels.first)
        guard case .ready = await settledPreview(model, for: panel) else {
            return XCTFail("expected a first preview")
        }

        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        await model.load()
        guard case .ready = model.previewState(for: panel) else {
            return XCTFail("the old preview should still be up during a reload")
        }
    }

    /// The card draws the board the way the viewer does — fitted, never
    /// overflowing the space it was given.
    func testAPreviewBoardFitsTheCard() throws {
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        let preview = PanelPreview(rows: 12, cols: 30,
                                   cells: [], message: nil)
        let box = CGSize(width: PanelCard.width, height: PanelCard.previewHeight)
        let layout = try XCTUnwrap(PanelPreviewBoard.layout(panel: panel, preview: preview, in: box))
        XCTAssertGreaterThan(layout.width, 0)
        XCTAssertLessThanOrEqual(layout.width, box.width + 0.5)
        XCTAssertLessThanOrEqual(layout.height, box.height + 0.5)
        XCTAssertEqual(layout.tiles.count, 12 * 30)
    }

    func testAPreviewBoardWithNoGridDrawsNothing() throws {
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        let empty = PanelPreview(rows: 0, cols: 0, cells: [], message: nil)
        let box = CGSize(width: PanelCard.width, height: PanelCard.previewHeight)
        XCTAssertNil(PanelPreviewBoard.layout(panel: panel, preview: empty, in: box))
    }

    /// A frame with no characters yet is a board of blanks, not a failure.
    func testAnEmptyFrameStillPreviewsAsABoard() throws {
        let frame = try JSONDecoder().decode(PanelFrame.self, from: Data(Fixtures.emptyFrameJSON.utf8))
        let preview = PanelPreview.make(from: frame, code62: .heart)
        XCTAssertEqual(preview.rows, 12)
        XCTAssertEqual(preview.cols, 30)
        XCTAssertTrue(preview.cells.isEmpty)
    }

    /// The card really does paint the board, not just reserve a hole for
    /// it: a board of red flaps must put red pixels on the card.
    func testTheCardPaintsTheBoardItself() throws {
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        let red = Array(repeating: Array(repeating: 63, count: 6), count: 3)
        let preview = PanelPreview(rows: 3, cols: 6,
                                   cells: BoardTables.cells(from: red, code62: .heart),
                                   message: nil)
        let size = CGSize(width: PanelCard.width + 40,
                          height: PanelCard.previewHeight + PanelCard.detailHeight + 40)
        let image = RenderHarness.image(PanelCard(panel: panel, preview: .ready(preview)) {},
                                        size: size)
        var redPixels = 0
        for y in stride(from: 10, to: Int(PanelCard.previewHeight), by: 8) {
            for x in stride(from: 10, to: Int(PanelCard.width), by: 8) {
                guard let pixel = image.pixel(x: x, y: y) else { continue }
                if pixel.r > 150 && pixel.g < 120 && pixel.b < 120 { redPixels += 1 }
            }
        }
        XCTAssertGreaterThan(redPixels, 20, "the board never made it onto the card")
    }

    func testTheCardRendersEveryPreviewState() async {
        let panel = try! JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        let ready = PanelPreview(rows: 2, cols: 3,
                                 cells: BoardTables.cells(from: [[8, 9, 0], [63, 0, 0]],
                                                          code62: .heart),
                                 message: "HI")
        RenderHarness.render(VStack {
            PanelCard(panel: panel, preview: .loading) {}
            PanelCard(panel: panel, preview: .ready(ready)) {}
            PanelCard(panel: panel, preview: .unavailable) {}
        })
    }

    func testTheCardRendersAPanelWithNoBoard() throws {
        let orphan = Fixtures.panelJSON
            .replacingOccurrences(of: "\"board_missing\":false", with: "\"board_missing\":true")
            .replacingOccurrences(of: "\"rows\":12", with: "\"rows\":null")
            .replacingOccurrences(of: "\"cols\":30", with: "\"cols\":null")
        let panel = try JSONDecoder().decode(Panel.self, from: Data(orphan.utf8))
        RenderHarness.render(PanelCard(panel: panel, preview: .unavailable) {})
    }

}

// MARK: - Focus and what the card says

extension PanelsScreenTests {

    private func decodedPanel(id: String = "abc123def456",
                              boardMissing: Bool = false) throws -> Panel {
        var json = Fixtures.panelJSON
            .replacingOccurrences(of: "\"id\":\"abc123def456\"", with: "\"id\":\"\(id)\"")
        if boardMissing {
            json = json.replacingOccurrences(of: "\"board_missing\":false",
                                             with: "\"board_missing\":true")
        }
        return try JSONDecoder().decode(Panel.self, from: Data(json.utf8))
    }

    /// A TV screen must open with something chosen, and the first panel is
    /// the thing someone came here for — not the Settings button.
    func testDefaultFocusIsTheFirstPanel() throws {
        let panels = [try decodedPanel(id: "a"), try decodedPanel(id: "b")]
        XCTAssertEqual(PanelsScreen.defaultFocusPanel(in: panels), "a")
    }

    /// A panel with no board is disabled, so opening on it would leave the
    /// screen with nothing focused at all.
    func testDefaultFocusSkipsAPanelWithNoBoard() throws {
        let panels = [try decodedPanel(id: "orphan", boardMissing: true),
                      try decodedPanel(id: "real")]
        XCTAssertEqual(PanelsScreen.defaultFocusPanel(in: panels), "real")
    }

    /// Every panel orphaned: still name one, rather than leaving the focus
    /// engine to guess.
    func testDefaultFocusFallsBackWhenEveryPanelIsOrphaned() throws {
        let panels = [try decodedPanel(id: "one", boardMissing: true),
                      try decodedPanel(id: "two", boardMissing: true)]
        XCTAssertEqual(PanelsScreen.defaultFocusPanel(in: panels), "one")
    }

    func testDefaultFocusOfAnEmptyListIsNothing() {
        XCTAssertNil(PanelsScreen.defaultFocusPanel(in: []))
    }

    /// The flaps are 13pt glyphs at card size — recognisable as a board,
    /// nowhere near readable across a room. So the card also says what the
    /// board says, in type someone can read.
    func testTheCardSaysWhatTheBoardSays() throws {
        let panel = try decodedPanel()
        let preview = PanelPreview(rows: 2, cols: 3, cells: [], message: "COFFEE\nIS READY")
        let card = PanelCard(panel: panel, preview: .ready(preview)) {}
        XCTAssertEqual(card.subtitle, "COFFEE IS READY")
        XCTAssertTrue(card.accessibilityLabel.contains("Living Room"))
        XCTAssertTrue(card.accessibilityLabel.contains("Board reads: COFFEE IS READY"))
    }

    /// A board with nothing on it falls back to describing the panel.
    func testACardWithNoMessageDescribesThePanel() throws {
        let panel = try decodedPanel()
        let blank = PanelPreview(rows: 12, cols: 30, cells: [], message: "  ")
        XCTAssertEqual(PanelCard(panel: panel, preview: .ready(blank)) {}.subtitle,
                       "30 × 12 · Built for a 65\" screen")
        XCTAssertEqual(PanelCard(panel: panel, preview: .loading) {}.subtitle,
                       "30 × 12 · Built for a 65\" screen")
    }

    func testAnOrphanedCardSaysSoRatherThanQuotingABoard() throws {
        let panel = try decodedPanel(boardMissing: true)
        let card = PanelCard(panel: panel, preview: .unavailable) {}
        XCTAssertEqual(card.subtitle, "No board")
        XCTAssertTrue(card.accessibilityLabel.contains("No board"))
    }

    /// Two cards to a row at 1920 x 1080, inside the safe inset and the
    /// padding the focus lift needs. Three made the flaps illegible.
    func testTwoCardsFitARowOnATVScreen() {
        // The scroll view is widened by exactly the focus padding it then
        // spends on its content, so the cards get the inset width.
        let usable = RenderHarness.tvSize.width - Fiesta.Metrics.safeInset * 2
        let spacing = Fiesta.Metrics.gutter + 16
        XCTAssertGreaterThanOrEqual(usable, PanelCard.width * 2 + spacing)
        XCTAssertLessThan(usable, PanelCard.width * 3 + spacing * 2)
    }
}

// MARK: - How the card sits on a near-black ground

extension PanelsScreenTests {

    /// A realistic board: 30 x 12 with three lines of text on it.
    private func filledBoard() -> PanelPreview {
        let cols = 30, rows = 12
        var grid = Array(repeating: Array(repeating: 0, count: cols), count: rows)
        func codes(_ text: String) -> [Int] {
            var row = text.uppercased().map { ch -> Int in
                guard let a = ch.asciiValue, a >= 65, a <= 90 else { return 0 }
                return Int(a) - 64
            }
            while row.count < cols { row.append(0) }
            return Array(row.prefix(cols))
        }
        grid[3] = codes("     GOOD MORNING JEFFRE")
        grid[5] = codes("     COFFEE IS READY")
        grid[7] = codes("     SIXTY EIGHT DEGREES")
        return PanelPreview(rows: rows, cols: cols,
                            cells: BoardTables.cells(from: grid, code62: .heart),
                            message: "GOOD MORNING JEFFRE")
    }

    private static let cardMargin = 40

    /// The card drawn at 1:1 on the app's own ground, with a margin round it.
    private func cardImage() throws -> UIImage {
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        let margin = CGFloat(Self.cardMargin * 2)
        return RenderHarness.image(
            ZStack {
                Fiesta.Colors.background
                PanelCard(panel: panel, preview: .ready(filledBoard())) {}
            },
            size: CGSize(width: PanelCard.width + margin,
                         height: PanelCard.previewHeight + PanelCard.detailHeight + margin))
    }

    private func luma(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Int {
        (Int(p.r) * 2 + Int(p.g) * 5 + Int(p.b)) / 8
    }

    /// The board must sit in the middle of its card.
    ///
    /// It did not: wrapping `BoardCanvas` — which already carries a fixed
    /// frame and paints its own background onto it — in a second flexible
    /// frame left the board hard against the left edge with every point of
    /// slack piled up on the right. Only a rendered pixel catches that;
    /// the layout it is handed is the correct size either way.
    func testTheBoardIsCentredInTheCard() throws {
        let image = try cardImage()
        let left = Self.cardMargin
        let right = left + Int(PanelCard.width) - 1

        // The board is the only pure black on the card: the ground is
        // #0e0d0b and the plate #181613.
        var firstBoard = Int.max
        var lastBoard = Int.min
        for y in stride(from: left + 30, to: left + Int(PanelCard.previewHeight) - 30, by: 17) {
            for x in left...right {
                guard let p = image.pixel(x: x, y: y) else { continue }
                guard p.r < 6, p.g < 6, p.b < 6 else { continue }
                firstBoard = min(firstBoard, x)
                lastBoard = max(lastBoard, x)
            }
        }
        XCTAssertLessThan(firstBoard, lastBoard, "no board was drawn at all")

        let leadingPlate = firstBoard - left
        let trailingPlate = right - lastBoard
        XCTAssertLessThanOrEqual(abs(leadingPlate - trailingPlate), 3,
                                 "board is off centre: \(leadingPlate)pt of plate on the left, "
                                 + "\(trailingPlate)pt on the right")
        XCTAssertGreaterThanOrEqual(leadingPlate, Int(PanelCard.boardInset),
                                    "the board should be mounted on the plate, not bled to the edge")
    }

    /// The card must have an edge.
    ///
    /// Against the old grey ground the plate was lighter than the app and
    /// that was edge enough. On a near-black ground the plate is a few
    /// values above it and the board on the card is pure black — DARKER
    /// than the ground — so the card read as a hole. The hairline is what
    /// draws the edge now, and it has to survive the surfaces moving again.
    func testTheCardHasAVisibleEdgeAgainstTheAppGround() throws {
        let image = try cardImage()
        let midCard = Self.cardMargin + Int(PanelCard.previewHeight) / 2
        let ground = try XCTUnwrap(image.pixel(x: 4, y: midCard))

        var brightest = 0
        for x in (Self.cardMargin - 3)...(Self.cardMargin + 3) {
            guard let p = image.pixel(x: x, y: midCard) else { continue }
            brightest = max(brightest, luma(p))
        }
        // The plate alone is only about 9 above the ground — not an edge
        // at ten feet. The hairline is about 34. Anything under 20 means
        // the hairline has gone.
        XCTAssertGreaterThan(brightest - luma(ground), 20,
                             "the card's edge is indistinguishable from the app ground")
    }

    /// Board black, app ground and the viewer's true black are three
    /// different colours and the card must not quietly merge them.
    func testTheCardKeepsBoardBlackApartFromTheAppGround() throws {
        let image = try cardImage()
        let ground = try XCTUnwrap(image.pixel(x: 4, y: Self.cardMargin + 20))
        XCTAssertGreaterThan(luma(ground), 4,
                             "the app ground must not be true black — that is the viewer's")
    }
}
