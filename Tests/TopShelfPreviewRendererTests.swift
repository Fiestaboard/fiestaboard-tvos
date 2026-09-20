import UIKit
import XCTest
@testable import FiestaBoardTV

@MainActor
final class TopShelfPreviewRendererTests: XCTestCase {
    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testRendersCurrentFrameAsFullSizeCarouselImage() throws {
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        let frame = try JSONDecoder().decode(PanelFrame.self, from: Data(Fixtures.frameJSON.utf8))
        let png = try XCTUnwrap(TopShelfPreviewRenderer.png(panel: panel, frame: frame))
        let image = try XCTUnwrap(UIImage(data: png))
        let attachment = XCTAttachment(image: image)
        attachment.name = "Top Shelf board preview"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(image.size.width, 1920)
        XCTAssertEqual(image.size.height, 1080)
        let margin = try XCTUnwrap(image.pixel(x: 20, y: 20))
        XCTAssertLessThan(Int(margin.r), 3)
        let center = try XCTUnwrap(image.pixel(x: 960, y: 540))
        XCTAssertLessThan(Int(center.r), 40, "the board preview should retain its dark flap surface")
    }

    func testPublisherCachesTheAvailablePanelsCurrentFrame() async throws {
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
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/api/panel/")

        await TopShelfPreviewPublisher.publish(panels: [panel], connection: connection,
                                               store: store)

        let item = try XCTUnwrap(store.items().first)
        XCTAssertEqual(item.panelID, panel.id)
        XCTAssertEqual(item.name, panel.name)
        XCTAssertNotNil(UIImage(data: try Data(contentsOf: store.imageURL(for: item))))
        XCTAssertTrue(StubURLProtocol.requests.contains { $0.url.path.hasSuffix("/frame") })
    }

    func testFrameFailureKeepsTheLastTopShelfPreview() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("topshelf-offline-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        let oldImage = Data([1, 2, 3])
        try store.replace([.init(panelID: panel.id, name: panel.name, imageData: oldImage)])
        let connection = ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.topshelf.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")

        await TopShelfPreviewPublisher.publish(panels: [panel], connection: connection,
                                               store: store)

        let retained = try XCTUnwrap(store.items().first)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: retained)), oldImage)
    }
}
