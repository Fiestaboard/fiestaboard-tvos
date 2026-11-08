import XCTest
@testable import FiestaBoardTV

/// A7 status wiring (after A6a #22): the hub's `PanelStatus`, read from
/// `GET /panel/{id}`, becomes the carousel's contextTitle — with A6a's
/// precedence on the hub's clock, and a bounded number of fetches.
@MainActor
final class TopShelfStatusWiringTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("topshelf-status-\(UUID().uuidString)")
    }

    override func tearDown() {
        StubURLProtocol.reset()
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func hubCase(_ name: String) throws -> (body: [String: Any], headers: [String: String]) {
        let url = TVSnapshot.repoRoot.appendingPathComponent("Tests/Fixtures/panel-status-v1.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        let c = try XCTUnwrap(cases.first { $0["name"] as? String == name }, name)
        return (c["body"] as! [String: Any], c["headers"] as! [String: String])
    }

    private func stub(_ name: String, as id: String) throws {
        var (body, headers) = try hubCase(name)
        body["id"] = id
        headers["Content-Type"] = "application/json"
        StubURLProtocol.enqueue(.init(status: 200, body: try JSONSerialization.data(withJSONObject: body), headers: headers),
                                for: "/api/panel/\(id)")
    }

    private func reading(_ name: String) async throws -> PanelReading {
        try stub(name, as: "lobby")
        let client = FiestaClient(baseURL: URL(string: "http://hub:4420")!, session: StubURLProtocol.makeSession())
        return try await client.panelReading(ref: "lobby")
    }

    /// Every hub case maps through A6a's chip precedence onto DD2's line.
    func testEveryHubCaseMapsToItsLine() async throws {
        let expected: [String: String?] = [
            "manual": nil,
            "schedule": "Now showing · Schedule",
            "override-with-expiry": "Now showing · Override · holds until 9:00 PM",
            "override-until-cancelled": "Now showing · Override · holds until canceled",
            "silenced-indicator": "Silenced · until 7:00 AM",
            "silenced-freeze": "Silenced · until 7:00 AM",
            "silenced-page": "Silenced · until 7:00 AM",
            "paused": "Paused",
            "paused+override": "Paused",
            "override+silenced": "Now showing · Override · holds until 9:00 PM",
            "board-missing": nil,
        ]
        for (name, line) in expected {
            let read = try await reading(name)
            let status = TopShelfStatus(reading: read, receivedAt: try XCTUnwrap(read.hubDate))
            XCTAssertEqual(TopShelfStatusLine.make(status, timeZone: zone), line, name)
        }
    }

    /// An old hub (no `status`) has nothing to say.
    func testAnOldHubHasNoLine() {
        let panel = try! JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        XCTAssertNil(TopShelfStatus(reading: PanelReading(panel: panel, hubDate: nil), receivedAt: Date()))
    }

    private func connectedApp() async throws -> (AppModel, TopShelfSnapshotStore) {
        let store = TopShelfSnapshotStore(directory: directory)
        let connection = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                         credentials: InMemoryCredentialStore(),
                                         clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        return (AppModel(connection: connection, topShelfStore: store), store)
    }

    private func panel(_ id: String) throws -> Panel {
        let json = Fixtures.panelJSON.replacingOccurrences(of: "abc123def456", with: id)
        return try JSONDecoder().decode(Panel.self, from: Data(json.utf8))
    }

    private var statusRequests: Int {
        StubURLProtocol.requests.filter { $0.url.path.hasPrefix("/api/panel/") && !$0.url.path.hasSuffix("/frame") }.count
    }

    /// Publishing the list fetches each panel's status once, then the
    /// carousel republishes with the line.
    func testPublishingFetchesTheStatusAndWritesTheLine() async throws {
        let (app, store) = try await connectedApp()
        let living = try panel("living")
        try stub("override-with-expiry", as: "living")
        await app.publishTopShelf(panels: [living])?.value
        await app.topShelfStatusTask?.value
        await app.topShelfRepublication?.value
        let item = try XCTUnwrap(store.items().first)
        XCTAssertEqual(statusRequests, 1)
        XCTAssertEqual(store.statusLine(for: item, now: Date())?.hasPrefix("Now showing · Override · holds until "), true,
                       "\(String(describing: item.statusLine))")
    }

    /// A refresh inside the interval reuses the status it already has: N
    /// frames arriving must not mean N × panels status fetches.
    func testAFreshStatusIsNotFetchedAgain() async throws {
        let (app, _) = try await connectedApp()
        let living = try panel("living")
        try stub("paused", as: "living")
        await app.publishTopShelf(panels: [living])?.value
        await app.topShelfStatusTask?.value
        for _ in 0..<3 {
            await app.publishTopShelf(panels: [living])?.value
            await app.topShelfStatusTask?.value
        }
        XCTAssertEqual(statusRequests, 1)
        XCTAssertLessThan(AppModel.topShelfStatusInterval, TopShelfSnapshotStore.statusLifetime,
                          "re-confirmed before the stale rule drops it")
    }

    /// Bounded: at most `topShelfStatusLimit` panels per refresh.
    func testStatusFetchesAreBounded() async throws {
        let (app, _) = try await connectedApp()
        app.topShelfStatusLimit = 2
        let panels = try ["a", "b", "c"].map(panel)
        for id in ["a", "b", "c"] { try stub("schedule", as: id) }
        await app.publishTopShelf(panels: panels)?.value
        await app.topShelfStatusTask?.value
        XCTAssertEqual(statusRequests, 2)
        XCTAssertEqual(AppModel.topShelfStatusConcurrency, 4, "the same four-at-a-time budget as frames")
    }

    /// A failed fetch leaves no line and is not retried inside the interval.
    func testAFailedFetchIsNotRetriedImmediately() async throws {
        let (app, store) = try await connectedApp()
        let living = try panel("living")
        StubURLProtocol.enqueue(.init(status: 500), for: "/api/panel/living")
        await app.publishTopShelf(panels: [living])?.value
        await app.topShelfStatusTask?.value
        await app.publishTopShelf(panels: [living])?.value
        await app.topShelfStatusTask?.value
        XCTAssertEqual(statusRequests, 1)
        XCTAssertNil(store.items().first?.statusLine)
    }
}
