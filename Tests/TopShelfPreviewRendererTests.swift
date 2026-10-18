import UIKit
import ImageIO
import os
import XCTest
@testable import FiestaBoardTV

@MainActor
final class TopShelfPreviewRendererTests: XCTestCase {
    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testPublishingReturnsBeforeWritingTheShelf() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        let connection = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        let panel = try MatrixDisplayTests.panel()

        let publication = TopShelfPreviewPublisher.publish(panels: [panel], connection: connection, store: store)

        XCTAssertTrue(store.items().isEmpty,
                      "Publishing must give input a turn before drawing, encoding or writing the shelf")
        await publication?.value
        XCTAssertEqual(store.items().map(\.panelID), [panel.id])
    }

    func testEncodingLeavesMainActorFreeAndCoalescesArrivalsToTheLatestFrame() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        let connection = try await connected()
        let panel = try MatrixDisplayTests.panel()
        let encoding = expectation(description: "first PNG encoding held off main")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let count = OSAllocatedUnfairLock(initialState: 0)
        let cache = TopShelfPreviewPublisher.Cache { image in
            XCTAssertFalse(Thread.isMainThread, "PNG compression must not block focus updates")
            let number = count.withLock { $0 += 1; return $0 }
            if number == 1 {
                encoding.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
            return Self.png(image)
        }
        TopShelfPreviewPublisher.publish(panels: [panel], previews: [panel.id: color(.red)],
                                         connection: connection, store: store, cache: cache)
        await fulfillment(of: [encoding], timeout: 3)
        // This main-actor code must run while the encoder is still blocked.
        // Reverting to synchronous encoding fails the gate, independently of
        // how quickly the particular simulator usually compresses PNGs.
        TopShelfPreviewPublisher.publish(panels: [panel], previews: [panel.id: color(.green)],
                                         connection: connection, store: store, cache: cache)
        let latest = TopShelfPreviewPublisher.publish(panels: [panel], previews: [panel.id: color(.blue)],
                                                     connection: connection, store: store, cache: cache)
        XCTAssertTrue(store.items().isEmpty)
        release.signal()
        await latest?.value

        XCTAssertEqual(count.withLock { $0 }, 2, "The superseded pending frame must never be encoded")
        let item = try XCTUnwrap(store.items().first)
        let image = try XCTUnwrap(UIImage(data: Data(contentsOf: store.imageURL(for: item))))
        let pixel = try XCTUnwrap(image.pixel(x: 960, y: 250))
        XCTAssertGreaterThan(pixel.b, pixel.r, "Only the latest blue frame belongs on Home")
        XCTAssertEqual(cache.images[panel.id]?.state, color(.blue))
    }

    func testClearDuringEncodingCannotBeUndoneByTheOldPublication() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        try store.replace([.init(panelID: "old", name: "Old", imageData: Data([1]))])
        let connection = try await connected()
        let panel = try MatrixDisplayTests.panel()
        let encoding = expectation(description: "old image encoding held")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let cache = TopShelfPreviewPublisher.Cache { image in
            encoding.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            return Self.png(image)
        }
        TopShelfPreviewPublisher.publish(panels: [panel], previews: [panel.id: color(.red)],
                                         connection: connection, store: store, cache: cache)
        await fulfillment(of: [encoding], timeout: 3)
        connection.signOut()
        let cleanup = TopShelfPreviewPublisher.clear(store: store, cache: cache)
        // A new connection before the old encoding ends defeats a simple
        // signed-out check. Generation invalidation must still reject it.
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://new-board:4420")!, displayName: "New")
        release.signal()
        await cleanup?.value
        XCTAssertTrue(store.items().isEmpty)
        XCTAssertTrue(cache.images.isEmpty)
    }

    func testRefreshInvalidationDiscardsEncodingEvenWithoutAReplacementPublication() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        try store.replace([.init(panelID: "kept", name: "Kept", imageData: Data([1]))])
        let connection = try await connected()
        let panel = try MatrixDisplayTests.panel()
        let encoding = expectation(description: "superseded refresh encoding held")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let cache = TopShelfPreviewPublisher.Cache { image in
            encoding.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            return Self.png(image)
        }
        let publication = TopShelfPreviewPublisher.publish(panels: [panel], previews: [panel.id: color(.red)],
                                                          connection: connection, store: store, cache: cache)
        await fulfillment(of: [encoding], timeout: 3)
        cache.invalidate()
        release.signal()
        await publication?.value
        XCTAssertEqual(store.items().map(\.panelID), ["kept"])
        XCTAssertTrue(cache.images.isEmpty)
    }

    private func connected() async throws -> ConnectionStore {
        let connection = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        return connection
    }

    private func color(_ color: BoardColor) -> PanelPreviewState {
        .ready(PanelPreview(rows: 1, cols: 1, cells: [[.color(color)]], message: nil))
    }

    nonisolated private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    func testFetchedPanelContentReplacesBrandArtworkWithoutDuplicateRequests() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        let connection = ConnectionStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        let app = AppModel(connection: connection, topShelfStore: store)
        app.publishTopShelf(panels: [panel])
        let panels = PanelsModel(app: app)

        StubURLProtocol.enqueue(.json(#"{"characters":[[63]],"message":"RED","rows":1,"cols":1}"#),
                                for: "/api/panel/")
        await panels.refreshPreviews(for: [panel])
        let red = try XCTUnwrap(store.items().first)
        let image = try XCTUnwrap(UIImage(data: Data(contentsOf: store.imageURL(for: red))))
        XCTAssertEqual(image.size.width / image.size.height, 16.0 / 9, accuracy: 0.001)
        let pigment = try XCTUnwrap(image.pixel(x: 960, y: 250))
        XCTAssertEqual(Int(pigment.r), 235, accuracy: 2)
        XCTAssertEqual(Int(pigment.g), 64, accuracy: 2)
        XCTAssertEqual(Int(pigment.b), 52, accuracy: 2)

        StubURLProtocol.enqueue(.json(#"{"characters":[[67]],"message":"BLUE","rows":1,"cols":1}"#),
                                for: "/api/panel/")
        await panels.refreshPreviews(for: [panel])
        let blue = try XCTUnwrap(store.items().first)
        XCTAssertNotEqual(red.imageFile, blue.imageFile, "A new frame must replace the Home card artwork")
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url.path.hasSuffix("/frame") }.count, 2,
                       "Top Shelf must reuse each frame already fetched for the panel list")
    }

    func testLateFrameCannotRepopulateClearedShelfAfterSigningBackIn() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        let connection = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        let panel = try MatrixDisplayTests.panel()
        let app = AppModel(connection: connection, topShelfStore: store)
        let model = PanelsModel(app: app)
        let received = expectation(description: "old frame held")
        var release: (() -> Void)?
        var stub = StubURLProtocol.Stub.json(Fixtures.frameJSON)
        stub.beforeReply = { reply in
            Task { @MainActor in release = reply; received.fulfill() }
        }
        StubURLProtocol.enqueue(stub, for: "/api/panel/")
        let refresh = Task { await model.refreshPreviews(for: [panel]) }
        await fulfillment(of: [received], timeout: 3)
        connection.signOut()
        let cleanup = app.clearTopShelf()
        // Reconnecting makes a simple isSignedOut check insufficient.
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://new-board:4420")!, displayName: "New Board")
        release?()
        await refresh.value
        await cleanup?.value
        XCTAssertTrue(store.items().isEmpty, "A previous board must not return to Home after its cache was cleared")
        XCTAssertNil(model.previews[panel.id], "A stale response must not become the current panel picture either")
    }

    func testSnapshotsPreserveSquareAndRoundLEDGeometry() throws {
        let preview = PanelPreview(rows: 1, cols: 1, cells: [[.color(.red)]], message: "RED")
        for shape in ["square", "round"] {
            let panel = try MatrixDisplayTests.panel(["render_style": "led_matrix", "device_model_spec": [
                "geometry": ["kind": "pixels", "width": 192, "height": 96],
                "appearance": ["pixelShape": shape, "dotRatio": 0.82]]])
            let pixels = try XCTUnwrap(TopShelfPreviewRenderer.image(panel: panel, preview: preview))
            let image = UIImage(cgImage: pixels)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Top Shelf \(shape) LEDs"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(image.size.width, 1920)
            XCTAssertEqual(image.size.height, 1080)
            XCTAssertEqual(Int(try XCTUnwrap(image.pixel(x: 69, y: 97)).r), 235, accuracy: 2)
            let corner = try XCTUnwrap(image.pixel(x: 65, y: 93))
            if shape == "square" { XCTAssertGreaterThan(corner.r, 200) }
            else { XCTAssertLessThan(corner.r, 80, "round LEDs must retain their dark corners") }
        }
    }

    func testBoardContentStaysClearOfHomeCardRoundedEdges() throws {
        let preview = PanelPreview(rows: 1, cols: 1, cells: [[.color(.red)]], message: "RED")
        let panel = try MatrixDisplayTests.panel(["render_style": "led_matrix"])
        let pixels = try XCTUnwrap(TopShelfPreviewRenderer.image(panel: panel, preview: preview))
        let image = UIImage(cgImage: pixels)
        // Home crops the corners and adds a focus rim. Lit edge LEDs need
        // breathing room inside the image instead of touching that crop.
        XCTAssertLessThan(try XCTUnwrap(image.pixel(x: 5, y: 65)).r, 80)
        XCTAssertLessThan(try XCTUnwrap(image.pixel(x: 1915, y: 1015)).r, 80)
    }

    func testPublisherUsesExplicitUnavailableArtworkWithoutTouchingTheNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("topshelf-render-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        let connection = ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.topshelf.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        StubURLProtocol.reset()

        await TopShelfPreviewPublisher.publish(panels: [panel], connection: connection, store: store)?.value

        let item = try XCTUnwrap(store.items().first)
        XCTAssertEqual(item.panelID, panel.id)
        XCTAssertEqual(item.name, panel.name)
        let image = try Data(contentsOf: store.imageURL(for: item))
        XCTAssertNotNil(UIImage(data: image))
        XCTAssertEqual(image, Self.png(try XCTUnwrap(TopShelfPreviewRenderer.unavailable)),
                       "No fetched frame means an explicit unavailable picture, never invented board content")
        // Fetching belongs to the caller; publishing only writes local images.
        XCTAssertTrue(StubURLProtocol.requests.isEmpty,
                      "publishing should not make requests, made \(StubURLProtocol.requests)")
    }

    func testPanelWithNoBoardIsLeftOutOfTheCarousel() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("topshelf-missing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        let connection = ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.topshelf.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")

        let missing = Fixtures.panelJSON.replacingOccurrences(of: #""board_missing":false"#,
                                                              with: #""board_missing":true"#)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(missing.utf8))
        XCTAssertTrue(panel.boardMissing, "fixture should describe a panel with no board")

        await TopShelfPreviewPublisher.publish(panels: [panel], connection: connection, store: store)?.value

        XCTAssertTrue(store.items().isEmpty,
                      "a panel with no board has nothing to open into")
    }

    func testSignedOutBoardPublishesNothing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("topshelf-signedout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        let existing = Data([1, 2, 3])
        try store.replace([.init(panelID: "one", name: "Kitchen", imageData: existing)])

        let connection = ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.topshelf.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        connection.signOut()
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))

        await TopShelfPreviewPublisher.publish(panels: [panel], connection: connection, store: store)?.value

        let retained = try XCTUnwrap(store.items().first)
        XCTAssertEqual(retained.panelID, "one")
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: retained)), existing)
    }
}
