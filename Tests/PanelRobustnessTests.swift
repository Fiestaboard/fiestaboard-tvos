import XCTest
@testable import FiestaBoardTV

/// Accelerated protocol/lifecycle checks, not a wall-clock or physical-TV soak.
/// Each frame reply is released by the test so slow consumers cannot skip a
/// failure through the production stream's bufferingNewest(1) policy.
final class PanelRobustnessTests: XCTestCase {
    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func client() -> FiestaClient {
        FiestaClient(baseURL: URL(string: "http://prod-tv.invalid:4420")!,
                     session: StubURLProtocol.makeSession())
    }

    func testMalformedFrameGeometryIsRejectedInsteadOfBecomingABlankBoard() async {
        let client = client()
        for body in ["{}", #"{"rows":1}"#, #"{"cols":1}"#,
                     #"{"rows":null,"cols":1}"#, #"{"rows":1,"cols":null}"#,
                     #"{"rows":"1","cols":1}"#, #"{"rows":1,"cols":true}"#] {
            StubURLProtocol.enqueue(.json(body), for: "/frame")
            do {
                _ = try await client.frame(ref: "1")
                XCTFail("Malformed geometry must not replace the last frame: \(body)")
            } catch FiestaError.decoding { /* The poller retains its last frame. */ }
            catch { XCTFail("Expected a decoding error for \(body), got \(error)") }
        }
    }

    func testRepeatedMalformedAndUnavailableFramesRetainContentThenRecover() async throws {
        let replies = AsyncStream<() -> Void>.makeStream()
        defer { replies.continuation.finish() }
        let cycles = 12
        let healthy = #"{"rows":1,"cols":1,"characters":[[8]],"message":"H","cells":[[{"type":"char","value":"H"}]],"layers":[{"x":0,"y":0,"width":1,"height":1,"rgba":"/wAA/w=="}]}"#
        let recovered = #"{"rows":1,"cols":1,"characters":[[9]],"message":"I"}"#
        for _ in 0..<cycles {
            for response in [StubURLProtocol.Stub.json(healthy), .json("{}"),
                             .json("{}", status: 503), .json(recovered)] {
                StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
                var held = response
                held.beforeReply = { replies.continuation.yield($0) }
                StubURLProtocol.enqueue(held, for: "/api/panel/1/frame")
            }
        }
        // Hold any next poll without publishing, even if the test consumer is
        // descheduled after the final expected snapshot.
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        var sentinel = StubURLProtocol.Stub.json(recovered)
        sentinel.beforeReply = { replies.continuation.yield($0) }
        StubURLProtocol.enqueue(sentinel, for: "/api/panel/1/frame")
        let store = PanelStore(client: client(), ref: "1", frameInterval: 0.001, configInterval: 0)
        defer { store.stop() }
        // A failed producer must end both waits, rather than hang the suite.
        let deadline = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            XCTFail("recovery simulation exceeded its deadline")
            replies.continuation.finish()
            store.stop()
        }
        defer { deadline.cancel() }
        var snapshots = store.snapshots().makeAsyncIterator()
        var pending = replies.stream.makeAsyncIterator()
        for cycle in 0..<cycles {
            var lastGood: PanelSnapshot?
            for phase in 0..<4 {
                let nextReply = await pending.next()
                let reply = try XCTUnwrap(nextReply, "missing frame reply, cycle \(cycle), phase \(phase)")
                reply()
                let nextSnapshot = await snapshots.next()
                let snapshot = try XCTUnwrap(nextSnapshot)
                let live = phase == 0 || phase == 3
                XCTAssertEqual(snapshot.connection, live ? .live : .stale, "cycle \(cycle), phase \(phase)")
                XCTAssertEqual(snapshot.rows, 1)
                XCTAssertEqual(snapshot.cols, 1)
                XCTAssertEqual(snapshot.cells, [[.character(phase == 3 ? "I" : "H")]])
                XCTAssertEqual(snapshot.message, live ? (phase == 3 ? "I" : "H") : nil)
                XCTAssertFalse(snapshot.deleted, "an outage is not a deleted display")
                if phase == 0 {
                    XCTAssertEqual(snapshot.richCells?.count, 1)
                    XCTAssertEqual(snapshot.layers.count, 1)
                    lastGood = snapshot
                } else if !live {
                    XCTAssertEqual(snapshot.richCells, lastGood?.richCells)
                    XCTAssertEqual(snapshot.layers, lastGood?.layers)
                } else {
                    XCTAssertNil(snapshot.richCells)
                    XCTAssertTrue(snapshot.layers.isEmpty, "recovery must clear obsolete pixel layers")
                }
            }
        }
        store.stop()
        let ended = await snapshots.next()
        XCTAssertNil(ended)
        let requests = StubURLProtocol.requests.filter { $0.url.path.hasSuffix("/frame") }.count
        XCTAssertTrue((cycles * 4...cycles * 4 + 1).contains(requests), "unbounded polling: \(requests)")
    }

    func testRepeatedStartStopReleasesStoresAndEachNewStreamGetsCurrentContent() async throws {
        for generation in 0..<24 {
            StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
            let code = generation.isMultiple(of: 2) ? 8 : 9
            StubURLProtocol.enqueue(.json("{\"rows\":1,\"cols\":1,\"characters\":[[\(code)]]}"), for: "/frame")
            var store: PanelStore? = PanelStore(client: client(), ref: "1")
            let deadline = stopAfterDeadline(store!)
            defer { deadline.cancel() }
            weak var released = store
            var snapshots = store!.snapshots().makeAsyncIterator()
            let next = await snapshots.next()
            let snapshot = try XCTUnwrap(next)
            XCTAssertEqual(snapshot.connection, .live)
            XCTAssertEqual(snapshot.cells, [[.character(generation.isMultiple(of: 2) ? "H" : "I")]])
            store!.stop()
            let ended = await snapshots.next()
            XCTAssertNil(ended)
            store = nil
            XCTAssertNil(released, "generation \(generation) retained its store")
            released = nil
        }
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url.path.hasSuffix("/frame") }.count, 24)
    }

    func testRevokedSessionEndsPollingAfterTheLastGoodFrame() async throws {
        let replies = AsyncStream<() -> Void>.makeStream()
        defer { replies.continuation.finish() }
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        var refused = StubURLProtocol.Stub.json("{}", status: 401)
        refused.beforeReply = { replies.continuation.yield($0) }
        StubURLProtocol.enqueue(refused, for: "/frame")
        let store = PanelStore(client: client(), ref: "1", frameInterval: 0.02)
        defer { store.stop() }
        let deadline = stopAfterDeadline(store) { replies.continuation.finish() }
        defer { deadline.cancel() }
        var snapshots = store.snapshots().makeAsyncIterator()
        let first = await snapshots.next()
        XCTAssertEqual(first?.connection, .live)
        var pending = replies.stream.makeAsyncIterator()
        let nextReply = await pending.next()
        let reply = try XCTUnwrap(nextReply)
        reply()
        let revoked = await snapshots.next()
        XCTAssertEqual(revoked?.connection, .unauthorized)
        XCTAssertEqual(revoked?.cells, first?.cells)
        XCTAssertNil(revoked?.message)
        let ended = await snapshots.next()
        XCTAssertNil(ended, "a rejected session must not keep polling")
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url.path.hasSuffix("/frame") }.count, 2)
    }

    private func stopAfterDeadline(_ store: PanelStore, unblock: @escaping () -> Void = {}) -> Task<Void, Never> {
        Task { [weak store] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            XCTFail("polling lifecycle exceeded its deadline")
            unblock()
            store?.stop()
        }
    }
}
