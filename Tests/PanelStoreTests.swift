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
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/panel/1")
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
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/panel/1")
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
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/panel/1")
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        // Nothing more enqueued: subsequent polls fail at the transport.

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store, timeout: 4) { $0.connection == .stale }
        XCTAssertEqual(snapshot?.connection, .stale)
        XCTAssertEqual(snapshot?.cells.first?.first, .character("H"),
                       "the last good frame must stay up")
    }

    func testADeletedPanelIsReportedNotRetriedForever() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelNotFound, status: 404), for: "/panel/1")
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(Fixtures.panelNotFound, status: 404), for: "/frame") }

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store, timeout: 4) { $0.deleted }
        XCTAssertEqual(snapshot?.deleted, true)
    }

    func testABlankBoardIsNotAnError() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/panel/1")
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(Fixtures.emptyFrameJSON), for: "/frame") }

        let store = makeStore()
        let snapshot = await firstSnapshot(from: store) { $0.panel != nil }
        XCTAssertEqual(snapshot?.connection, .live)
        XCTAssertFalse(snapshot?.deleted ?? true)
        XCTAssertTrue(snapshot?.cells.allSatisfy { $0.allSatisfy { $0 == .blank } } ?? false)
    }

    func testStopEndsTheStream() async {
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/panel/1")
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
}
