import UIKit
import XCTest
@testable import FiestaBoardTV

@MainActor
final class TopShelfPreviewRendererTests: XCTestCase {
    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testPosterIsTheBrandMarkOnTheBrandField() throws {
        let png = try XCTUnwrap(TopShelfPreviewRenderer.poster)
        let image = try XCTUnwrap(UIImage(data: png))
        let attachment = XCTAttachment(image: image)
        attachment.name = "Top Shelf poster"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertEqual(image.size.width, 1920)
        XCTAssertEqual(image.size.height, 1080)

        let margin = try XCTUnwrap(image.pixel(x: 20, y: 20))
        XCTAssertEqual([Int(margin.r), Int(margin.g), Int(margin.b)], [0xf5, 0xa6, 0x23],
                       "Home should see the brand field, not a dark board")

        // The mark's centre falls on the tortilla, which is nothing like the
        // near-black a rendered board would put here.
        let centre = try XCTUnwrap(image.pixel(x: 960, y: 540))
        XCTAssertGreaterThan(Int(centre.r), 120, "the taco should be drawn over the field")
        XCTAssertNotEqual([Int(centre.r), Int(centre.g), Int(centre.b)], [0xf5, 0xa6, 0x23])
    }

    func testPublisherWritesOnePosterPerAvailablePanelWithoutTouchingTheNetwork() async throws {
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

        TopShelfPreviewPublisher.publish(panels: [panel], connection: connection, store: store)

        let item = try XCTUnwrap(store.items().first)
        XCTAssertEqual(item.panelID, panel.id)
        XCTAssertEqual(item.name, panel.name)
        XCTAssertNotNil(UIImage(data: try Data(contentsOf: store.imageURL(for: item))))
        // The poster is the brand mark, so publishing asks the board for
        // nothing — the panel list the caller already holds is enough.
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

        TopShelfPreviewPublisher.publish(panels: [panel], connection: connection, store: store)

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

        TopShelfPreviewPublisher.publish(panels: [panel], connection: connection, store: store)

        let retained = try XCTUnwrap(store.items().first)
        XCTAssertEqual(retained.panelID, "one")
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: retained)), existing)
    }
}
