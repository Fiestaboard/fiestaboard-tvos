import XCTest
import Observation
@testable import FiestaBoardTV

@MainActor
final class PolishTests: XCTestCase {
    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func app() async throws -> AppModel {
        let connection = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                         credentials: InMemoryCredentialStore(),
                                         clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://board.local:4420")!, displayName: "Board")
        return AppModel(connection: connection)
    }

    private func snapshot(connection: ConnectionState = .live, cells: [[BoardCell]] = [[.character("A")]]) throws -> PanelSnapshot {
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        return PanelSnapshot(panel: panel, cells: cells, rows: 1, cols: 1,
                             connection: connection, dimmed: false, deleted: false)
    }

    func testIdenticalPollDoesNotInvalidateTheViewer() async throws {
        let model = ViewerModel(app: try await app(), ref: "1")
        model.apply(try snapshot())
        let changes = PolishChangeCounter()
        withObservationTracking({ _ = model.snapshot }, onChange: { changes.increment() })
        model.apply(try snapshot())
        XCTAssertEqual(changes.value, 0, "an unchanged poll must not schedule another board render")
        model.apply(try snapshot(connection: .stale))
        XCTAssertEqual(changes.value, 1, "connection changes still need immediate feedback")
    }

    func testViewerReusesLayoutForChromeAndConnectionUpdates() async throws {
        let model = ViewerModel(app: try await app(), ref: "1")
        model.apply(try snapshot())
        let screen = CGSize(width: 1920, height: 1080)
        let first = try model.layout(for: screen)
        model.showOverlay()
        model.apply(try snapshot(connection: .stale))
        let next = try model.layout(for: screen)
        let reusesStorage = first.tiles.withUnsafeBufferPointer { a in
            next.tiles.withUnsafeBufferPointer { b in a.baseAddress == b.baseAddress }
        }
        XCTAssertTrue(reusesStorage, "chrome and connection changes must reuse the prepared tile array")
        let smaller = try model.layout(for: CGSize(width: 960, height: 540))
        XCTAssertEqual(smaller.tileHeight, first.tileHeight / 2, accuracy: 0.001)
        model.apply(try snapshot(cells: [[.character("B")]]))
        XCTAssertEqual(try model.layout(for: screen).tiles.first?.cell, .character("B"))
        model.stop()
    }

    func testUnchangedMatrixPollDoesNotInvalidateResizeChrome() async throws {
        let model = ViewerModel(app: try await app(), ref: "1")
        let panel = try MatrixDisplayTests.panel(["render_style": "led_matrix"])
        let snapshot = PanelSnapshot(panel: panel, cells: [], rows: 1, cols: 1,
                                     connection: .live, dimmed: false, deleted: false)
        model.apply(snapshot)
        let changes = PolishChangeCounter()
        withObservationTracking({ _ = model.resizeOfferVisible }, onChange: { changes.increment() })
        model.apply(snapshot)
        XCTAssertEqual(changes.value, 0)
        model.resizeOfferVisible = true
        model.apply(snapshot)
        XCTAssertFalse(model.resizeOfferVisible)
    }

    private func loadBrowser(_ app: AppModel) async -> PanelsModel {
        let model = PanelsModel(app: app)
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        await model.load()
        model.stopPreviews()
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame")
        await model.refreshPreviews(for: model.panels)
        return model
    }

    func testReturningToPanelsImmediatelyRestoresCardsAndPreviewsEvenOffline() async throws {
        let app = try await app()
        let original = await loadBrowser(app)
        let restored = PanelsModel(app: app)
        XCTAssertEqual(restored.panels, original.panels)
        XCTAssertEqual(restored.previews, original.previews)
        XCTAssertFalse(restored.panels.isEmpty)
        // A refresh that fails should keep the cached cards available.
        await restored.load()
        XCTAssertNotNil(restored.errorMessage)
        XCTAssertEqual(restored.panels, original.panels)
    }

    func testPanelBrowserCacheCannotCrossConnectionsOrSignOut() async throws {
        let app = try await app()
        _ = await loadBrowser(app)
        app.connection.signOut()
        XCTAssertTrue(PanelsModel(app: app).panels.isEmpty)
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await app.connection.connect(to: URL(string: "http://other.local:4420")!, displayName: "Other")
        XCTAssertTrue(PanelsModel(app: app).panels.isEmpty)
        app.clearTopShelf()
        XCTAssertTrue(PanelsModel(app: app).previews.isEmpty)
    }

    func testBackgroundRefreshDiscardsPreviewsForReassignedAndRemovedPanels() async throws {
        let app = try await app()
        let original = await loadBrowser(app)
        let previous = try XCTUnwrap(original.panels.first)
        let reassigned = try MatrixDisplayTests.panel(["board_id": "replacement-board"])
        let refreshing = PanelsModel(app: app)
        let started = expectation(description: "replacement preview fetching")
        let reply = PolishReplyGate()
        var response = StubURLProtocol.Stub.json(Fixtures.emptyFrameJSON)
        response.beforeReply = { finish in reply.store(finish); started.fulfill() }
        StubURLProtocol.enqueue(response, for: "/frame")
        let task = Task { await refreshing.refreshPreviews(for: [reassigned]) }
        await fulfillment(of: [started], timeout: 2)
        if case .ready = refreshing.previews[previous.id] {
            XCTFail("the previous board's message must not stand in for the replacement")
        }
        reply.finish()
        await task.value
        let restored = PanelsModel(app: app)
        XCTAssertEqual(restored.panels.first?.boardId, "replacement-board")
        await refreshing.refreshPreviews(for: [])
        XCTAssertTrue(PanelsModel(app: app).previews.isEmpty)
        XCTAssertTrue(PanelsModel(app: app).panels.isEmpty)
    }

    func testOlderRefreshCannotClearTheNewRefreshSpinner() async throws {
        let model = PanelsModel(app: try await app())
        let firstStarted = expectation(description: "first request started")
        let secondStarted = expectation(description: "second request started")
        let firstReply = PolishReplyGate()
        let secondReply = PolishReplyGate()
        var first = StubURLProtocol.Stub.json(Fixtures.panelsList)
        first.beforeReply = { reply in firstReply.store(reply); firstStarted.fulfill() }
        var second = StubURLProtocol.Stub.json(Fixtures.panelsList)
        second.beforeReply = { reply in secondReply.store(reply); secondStarted.fulfill() }
        StubURLProtocol.enqueue(first, for: "/api/panels")
        StubURLProtocol.enqueue(second, for: "/api/panels")
        let one = Task { await model.load() }
        await fulfillment(of: [firstStarted], timeout: 2)
        let two = Task { await model.load() }
        await fulfillment(of: [secondStarted], timeout: 2)
        firstReply.finish()
        await one.value
        XCTAssertTrue(model.isLoading)
        secondReply.finish()
        await two.value
        XCTAssertFalse(model.isLoading)
        model.stopPreviews()
    }

    func testConnectionChangeClearsTheOldModelsPendingPreview() async throws {
        let app = try await app()
        let model = PanelsModel(app: app)
        let panel = try MatrixDisplayTests.panel()
        let started = expectation(description: "old frame held")
        let reply = PolishReplyGate()
        var response = StubURLProtocol.Stub.json(Fixtures.frameJSON)
        response.beforeReply = { finish in reply.store(finish); started.fulfill() }
        StubURLProtocol.enqueue(response, for: "/frame")
        let refresh = Task { await model.refreshPreviews(for: [panel]) }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(model.previews[panel.id], .loading)
        app.connection.signOut()
        app.clearTopShelf()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await app.connection.connect(to: URL(string: "http://other.local:4420")!, displayName: "Other")
        reply.finish()
        await refresh.value
        XCTAssertTrue(model.previews.isEmpty)
        XCTAssertTrue(model.panels.isEmpty)
        XCTAssertTrue(PanelsModel(app: app).previews.isEmpty)
    }

    func testOldPreviewCleanupPreservesANewerConnectionsCards() async throws {
        let app = try await app()
        let model = PanelsModel(app: app)
        let panel = try MatrixDisplayTests.panel()
        let started = expectation(description: "old frame held")
        let reply = PolishReplyGate()
        var response = StubURLProtocol.Stub.json(Fixtures.frameJSON)
        response.beforeReply = { finish in reply.store(finish); started.fulfill() }
        StubURLProtocol.enqueue(response, for: "/frame")
        let oldRefresh = Task { await model.refreshPreviews(for: [panel]) }
        await fulfillment(of: [started], timeout: 2)
        app.connection.signOut()
        app.clearTopShelf()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await app.connection.connect(to: URL(string: "http://other.local:4420")!, displayName: "Other")
        StubURLProtocol.enqueue(.json(Fixtures.emptyFrameJSON), for: "/frame")
        await model.refreshPreviews(for: [panel])
        let currentPreview = model.previews[panel.id]
        guard case .ready = currentPreview else {
            reply.finish()
            await oldRefresh.value
            return XCTFail("the replacement connection must have a fetched preview")
        }
        reply.finish()
        await oldRefresh.value
        XCTAssertEqual(model.previews[panel.id], currentPreview)
        XCTAssertEqual(model.panels, [panel])
    }
}

final class TopShelfPolishTests: XCTestCase {
    func testUnchangedPublicationDoesNotRewriteTheManifestButRepairsPurgedImages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        let previews = [TopShelfSnapshotStore.Preview(panelID: "one", name: "Kitchen", imageData: Data([1, 2, 3]))]
        XCTAssertTrue(try store.replace(previews))
        let manifest = directory.appendingPathComponent("manifest.json")
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: manifest.path)
        XCTAssertFalse(try store.replace(previews), "unchanged content should not ask Home to reload")
        let stamp = try FileManager.default.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date
        XCTAssertEqual(stamp, oldDate)
        let item = try XCTUnwrap(store.items().first)
        let imageURL = store.imageURL(for: item)
        try FileManager.default.removeItem(at: imageURL)
        XCTAssertTrue(try store.replace(previews), "a purged image needs a Home refresh")
        XCTAssertEqual(try Data(contentsOf: imageURL), Data([1, 2, 3]))
        try FileManager.default.removeItem(at: manifest)
        XCTAssertTrue(try store.replace(previews))
        XCTAssertEqual(store.items().count, 1)
    }

    func testClearingRepairsAnUnreadableManifest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = directory.appendingPathComponent("manifest.json")
        try Data("broken".utf8).write(to: manifest)
        try TopShelfSnapshotStore(directory: directory).clear()
        XCTAssertEqual(try JSONDecoder().decode([TopShelfSnapshotStore.Item].self, from: Data(contentsOf: manifest)), [])
    }
}

private final class PolishReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: (() -> Void)?
    func store(_ reply: @escaping () -> Void) { lock.withLock { self.reply = reply } }
    func finish() { lock.withLock { reply }?() }
}

private final class PolishChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
