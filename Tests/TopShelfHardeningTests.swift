import XCTest
@testable import FiestaBoardTV

/// A7b — the #24 review follow-ups (`program/reviews/pr-tvos-24-review.md`).
///
/// (S3, deep-link hardening, shipped in #32.)
/// S1: frames and statuses together never put more than four requests on a
/// hub at once. S2: the status concurrency and the hub-switch clearing are
/// tested, not just asserted as constants. N1: each panel's `statusAt` is
/// its own answer's time.
@MainActor
final class TopShelfHardeningTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("topshelf-hardening-\(UUID().uuidString)")
    }

    override func tearDown() {
        StubURLProtocol.reset()
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func connectedApp(host: String = "http://host:4420") async throws -> (AppModel, TopShelfSnapshotStore) {
        let store = TopShelfSnapshotStore(directory: directory)
        let connection = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                         credentials: InMemoryCredentialStore(),
                                         clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: host)!, displayName: "Board")
        return (AppModel(connection: connection, topShelfStore: store), store)
    }

    // MARK: S1/S2 — the request budget

    private func panel(_ id: String) throws -> Panel {
        let json = Fixtures.panelJSON.replacingOccurrences(of: "abc123def456", with: id)
        return try JSONDecoder().decode(Panel.self, from: Data(json.utf8))
    }

    /// Records the most requests a hub ever had in flight at once.
    final class InFlight: @unchecked Sendable {
        private let lock = NSLock()
        private var now = 0
        private(set) var peak = 0
        func held(_ stub: StubURLProtocol.Stub, for seconds: Double = 0.15) -> StubURLProtocol.Stub {
            var stub = stub
            stub.beforeReply = { [self] reply in
                lock.lock(); now += 1; peak = max(peak, now); lock.unlock()
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [self] in
                    lock.lock(); now -= 1; lock.unlock()
                    reply()
                }
            }
            return stub
        }
        var maximum: Int { lock.lock(); defer { lock.unlock() }; return peak }
    }

    private func statusStub(_ id: String) -> StubURLProtocol.Stub {
        .json(Fixtures.panelJSON.replacingOccurrences(of: "abc123def456", with: id))
    }

    private var statusRequests: [URL] {
        StubURLProtocol.requests.map(\.url).filter { $0.path.hasPrefix("/api/panel/") && !$0.path.hasSuffix("/frame") }
    }

    /// S2 (mutant M6): the status group really holds four at a time.
    func testStatusFetchesRunFourAtATime() async throws {
        let (app, _) = try await connectedApp()
        let ids = ["a", "b", "c", "d", "e", "f", "g"]
        let probe = InFlight()
        for id in ids { StubURLProtocol.enqueue(probe.held(statusStub(id)), for: "/api/panel/\(id)") }
        await app.publishTopShelf(panels: try ids.map(panel))?.value
        await app.topShelfStatusTask?.value
        XCTAssertEqual(statusRequests.count, ids.count)
        XCTAssertEqual(probe.maximum, AppModel.topShelfStatusConcurrency, "exactly the budget, never more")
    }

    /// S1: on the first load, frames and statuses share the hub's budget:
    /// statuses wait for the frame batch, so a Pi never sees more than four.
    func testFramesAndStatusesNeverExceedFourTogether() async throws {
        let (app, _) = try await connectedApp()
        let ids = ["a", "b", "c", "d", "e", "f"]
        let probe = InFlight()
        let frame = #"{"characters":[[1]],"message":"A","rows":1,"cols":1}"#
        for id in ids {
            StubURLProtocol.enqueue(probe.held(.json(frame)), for: "/api/panel/\(id)/frame")
            StubURLProtocol.enqueue(probe.held(statusStub(id)), for: "/api/panel/\(id)")
        }
        let panels = try ids.map(panel)
        await PanelsModel(app: app).refreshPreviews(for: panels)
        await app.topShelfStatusTask?.value
        XCTAssertEqual(statusRequests.count, ids.count, "statuses still load, after the frames")
        XCTAssertLessThanOrEqual(probe.maximum, 4, "frames + statuses in flight at once")
    }

    /// S2 (mutant M7): a hub switch clears the cached statuses and attempts,
    /// so the new hub's panels are fetched at once, not after five minutes.
    func testAHubSwitchFetchesTheNewHubsStatusesAtOnce() async throws {
        let (app, _) = try await connectedApp(host: "http://first:4420")
        StubURLProtocol.enqueue(statusStub("a"), for: "/api/panel/a")
        await app.publishTopShelf(panels: [try panel("a")])?.value
        await app.topShelfStatusTask?.value
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await app.connection.connect(to: URL(string: "http://second:4420")!, displayName: "Second")
        StubURLProtocol.enqueue(statusStub("a"), for: "/api/panel/a")
        await app.publishTopShelf(panels: [try panel("a")])?.value
        await app.topShelfStatusTask?.value
        XCTAssertEqual(statusRequests.map { $0.host }, ["first", "second"])
    }

    /// N1: each panel's line is stamped with its own answer, not the batch end.
    func testEachStatusIsStampedWithItsOwnAnswer() async throws {
        let (app, store) = try await connectedApp()
        var fast = StubURLProtocol.Stub.json(try overrideBody("a"), status: 200)
        fast.beforeReply = { $0() }
        StubURLProtocol.enqueue(fast, for: "/api/panel/a")
        var slow = StubURLProtocol.Stub.json(try overrideBody("b"), status: 200)
        slow.beforeReply = { reply in DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { reply() } }
        StubURLProtocol.enqueue(slow, for: "/api/panel/b")
        await app.publishTopShelf(panels: [try panel("a"), try panel("b")])?.value
        await app.topShelfStatusTask?.value
        await app.topShelfRepublication?.value
        let items = Dictionary(uniqueKeysWithValues: store.items().map { ($0.panelID, $0) })
        let a = try XCTUnwrap(items["a"]?.statusAt), b = try XCTUnwrap(items["b"]?.statusAt)
        XCTAssertGreaterThan(b.timeIntervalSince(a), 0.4, "a's line is as old as a's answer")
    }

    private func overrideBody(_ id: String) throws -> String {
        let url = TVSnapshot.repoRoot.appendingPathComponent("Tests/Fixtures/panel-status-v1.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        var body = try XCTUnwrap(cases.first { $0["name"] as? String == "override-until-cancelled" }?["body"] as? [String: Any])
        body["id"] = id
        return String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    }
}
