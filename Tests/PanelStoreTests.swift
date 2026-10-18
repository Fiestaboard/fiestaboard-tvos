import XCTest
@testable import FiestaBoardTV

final class PanelStoreTests: XCTestCase {

    private func makeStore(ref: String = "1") -> PanelStore {
        PanelStore(client: FiestaClient(baseURL: URL(string: "http://host:4420")!,
                                        session: StubURLProtocol.makeSession()),
                   ref: ref,
                   frameInterval: 0.02,
                   configInterval: 0.05)
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    /// Wait for the first snapshot matching `predicate`, or fail.
    private func firstSnapshot(from store: PanelStore,
                               timeout: TimeInterval = 3,
                               where predicate: @escaping (PanelSnapshot) -> Bool) async -> PanelSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        for await snapshot in store.snapshots() {
            if predicate(snapshot) { store.stop(); return snapshot }
            if Date() > deadline { store.stop(); return nil }
        }
        return nil
    }

    func testPublishesDecodedCellsFromTheFrame() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame") }

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store) { !$0.cells.isEmpty }
        XCTAssertEqual(snapshot?.cells.first?.first, .character("H"))
        XCTAssertEqual(snapshot?.cells.first?[1], .character("I"))
        XCTAssertEqual(snapshot?.cells[1].first, .color(.red))
        XCTAssertEqual(snapshot?.connection, .live)
    }

    /// The panel's device decides code 62, so the store must apply the
    /// panel's glyph rather than a default.
    func testAppliesThePanelsCode62Glyph() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        let heartFrame = #"{"characters":[[62]],"message":null,"rows":1,"cols":1,"updated_at":null}"#
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(heartFrame), for: "/frame") }

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store) { !$0.cells.isEmpty }
        // The fixture panel is a note_array, so code 62 is a heart.
        XCTAssertEqual(snapshot?.cells.first?.first, .character("♥"))
    }

    /// The contract that matters most on a wall: a dropped connection keeps
    /// the last frame on screen and only flags itself.
    func testALostConnectionKeepsTheLastFrameAndGoesStale() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        // Nothing more enqueued: subsequent polls fail at the transport.

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store, timeout: 4) { $0.connection == .stale }
        XCTAssertEqual(snapshot?.connection, .stale)
        XCTAssertEqual(snapshot?.cells.first?.first, .character("H"),
                       "the last good frame must stay up")
    }

    /// Both halves of the name. "Reported" is the flag; "not retried" is the
    /// `if !deleted` around the frame fetch, and only the flag was asserted —
    /// the six 404s queued below were never consumed either way, so a store
    /// that went on polling a panel the board says is gone read the same.
    func testADeletedPanelIsReportedNotRetriedForever() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelNotFound, status: 404), for: "/api/panel/1")
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(Fixtures.panelNotFound, status: 404), for: "/frame") }

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store, timeout: 4) { $0.deleted }
        XCTAssertEqual(snapshot?.deleted, true)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url.path.hasSuffix("/frame") },
                       "a deleted panel has no frames to ask for: \(StubURLProtocol.requests.map(\.url.path))")
    }

    func testABlankBoardIsNotAnError() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(Fixtures.emptyFrameJSON), for: "/frame") }

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store) { $0.panel != nil }
        XCTAssertEqual(snapshot?.connection, .live)
        XCTAssertFalse(snapshot?.deleted ?? true)
        // The grid has to be BUILT, not merely free of non-blanks:
        // `allSatisfy` on an empty array is true, so the blankness assertion
        // below passed just as happily for a store that published no cells at
        // all — which is a viewer with nothing on it, not a blank board.
        XCTAssertEqual(snapshot?.rows, 12)
        XCTAssertEqual(snapshot?.cols, 30)
        XCTAssertEqual(snapshot?.cells.count, 12)
        XCTAssertEqual(snapshot?.cells.first?.count, 30)
        XCTAssertTrue(snapshot?.cells.allSatisfy { $0.allSatisfy { $0 == .blank } } ?? false)
    }

    func testStopEndsTheStream() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        for _ in 0..<10 { StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame") }

        let store = makeStore()
        var count = 0
        for await _ in store.snapshots() {
            count += 1
            if count == 2 { store.stop() }
            if count > 50 { XCTFail("stream did not end"); break }
        }
        XCTAssertGreaterThanOrEqual(count, 2)
    }

    func testDefaultCadencesMatchTheWebViewer() {
        XCTAssertEqual(PanelStore.frameIntervalDefault, 2.0)
        XCTAssertEqual(PanelStore.configIntervalDefault, 10.0)
    }

    // MARK: What the board says

    func testTheFramesMessageReachesTheSnapshot() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame") }

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store) { !$0.cells.isEmpty }
        XCTAssertEqual(snapshot?.message, "HI")
    }

    /// The flaps keep their last frame during an outage, but the message is a
    /// claim about the present tense: a panel that is gone must stop speaking.
    func testADeletedPanelStopsSpeakingItsLastMessage() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(Fixtures.panelNotFound, status: 404), for: "/frame") }

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store, timeout: 4) { $0.deleted }
        XCTAssertNil(snapshot?.message)
    }

    // MARK: Sessions

    /// A store polling the way the viewer polls: through `ConnectionStore`,
    /// which is the app's one place that spends a stored credential on an
    /// expired session.
    private func makeAuthorizedStore(ref: String = "1") async throws -> PanelStore {
        let host = URL(string: "http://host:4420")!
        let credentials = InMemoryCredentialStore()
        try credentials.save(StoredCredential(username: "jeffre", password: "pw"),
                             for: host.absoluteString)
        let connection = ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.panelstore.\(UUID().uuidString)")!,
            credentials: credentials,
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: host, displayName: "Board")
        return PanelStore(runner: connection, ref: ref, frameInterval: 0.02, configInterval: 0.05)
    }

    private static let refused = #"{"detail":"Not authenticated"}"#

    /// The wall-mounted case: the session lapses, nobody is holding a remote,
    /// and the board must come back on its own.
    func testAnExpiredSessionIsRenewedInsteadOfGoingStale() async throws {
        let store = try await makeAuthorizedStore()
        StubURLProtocol.enqueue(.json(Self.refused, status: 401), for: "/api/panel/1")
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame") }

        let snapshot = await firstSnapshot(from: store) { !$0.cells.isEmpty }
        XCTAssertEqual(snapshot?.connection, .live)
        XCTAssertEqual(snapshot?.cells.first?.first, .character("H"))
        XCTAssertEqual(loginCount, 1, "exactly one silent re-login, not one per request")
    }

    /// And the case that must not become a request storm: a credential the
    /// board will keep refusing.
    func testARefusedCredentialReportsUnauthorizedWithoutSpinning() async throws {
        let store = try await makeAuthorizedStore()
        // Every path under the panel — config and frame alike — is refused.
        for _ in 0..<20 {
            StubURLProtocol.enqueue(.json(Self.refused, status: 401), for: "/api/panel/1")
        }
        StubURLProtocol.enqueue(.json(Self.refused, status: 401), for: "/api/auth/login")

        let snapshot = await firstSnapshot(from: store, timeout: 4) { $0.connection == .unauthorized }
        XCTAssertEqual(snapshot?.connection, .unauthorized,
                       "a 401 is not `.stale`: waiting does not mend it")
        XCTAssertFalse(snapshot?.deleted ?? true, "a refused request is not a deleted panel")
        XCTAssertLessThanOrEqual(loginCount, 1,
                                 "a rejected credential must not be spent again on every tick")
    }

    private var loginCount: Int {
        StubURLProtocol.requests.filter { $0.url.path.hasSuffix("/auth/login") }.count
    }
}

/// Lives here rather than in a file of its own: `BoardSpeech` exists only to
/// fill `PanelSnapshot.message`'s side of the viewer's one VoiceOver element,
/// and a new test file would have to be added to the target by hand.
final class BoardSpeechTests: XCTestCase {

    func testTheServersMessageWinsOverTheFlaps() {
        XCTAssertEqual(BoardSpeech.spoken(message: "Taco night", cells: [[.character("X")]]),
                       "Taco night")
    }

    /// A centred row is one word in twenty blanks; read literally that is a
    /// long silence.
    func testPaddingIsNotReadAsSilence() {
        XCTAssertEqual(BoardSpeech.spoken(message: "   HI\n  THERE ", cells: []), "HI THERE")
    }

    func testTheFlapsAreReadBackWhenThereIsNoMessage() {
        let cells: [[BoardCell]] = [
            [.blank, .character("H"), .character("I"), .blank],
            [.blank, .blank, .blank, .blank],
            [.character("Y"), .character("O"), .blank, .blank]
        ]
        XCTAssertEqual(BoardSpeech.spoken(message: nil, cells: cells), "HI, YO")
    }

    func testABlankBoardStillSaysSomething() {
        XCTAssertEqual(BoardSpeech.spoken(message: nil, cells: []), "Blank")
        XCTAssertEqual(BoardSpeech.spoken(message: "   ", cells: [[.blank, .blank]]), "Blank")
    }

    /// A flag or a block of colour has no text, but it is not blank either.
    func testAColourOnlyBoardIsNotReportedAsBlank() {
        XCTAssertEqual(BoardSpeech.spoken(message: nil, cells: [[.color(.red), .color(.blue)]]),
                       "Coloured flaps, no text")
    }
}
