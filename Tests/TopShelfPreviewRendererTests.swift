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
            if number == 1 { // the red @1x; its @2x follows (A7: two encodes per hero)
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

        XCTAssertEqual(count.withLock { $0 }, 4,
                       "The superseded pending frame must never be encoded (red and blue, each at @1x and @2x)")
        let item = try XCTUnwrap(store.items().first)
        let image = try XCTUnwrap(UIImage(data: Data(contentsOf: store.imageURL(for: item))))
        let slot = TopShelfPreviewRenderer.boardSlot
        let pixel = try XCTUnwrap(image.pixel(x: Int(slot.midX), y: Int(slot.midY)))
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
        let first = OSAllocatedUnfairLock(initialState: true)
        let cache = TopShelfPreviewPublisher.Cache { image in
            // Hold the first encode only (A7 encodes @1x then @2x).
            if first.withLock({ let was = $0; $0 = false; return was }) {
                encoding.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
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
        let first = OSAllocatedUnfairLock(initialState: true)
        let cache = TopShelfPreviewPublisher.Cache { image in
            // Hold the first encode only (A7 encodes @1x then @2x).
            if first.withLock({ let was = $0; $0 = false; return was }) {
                encoding.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
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
        // Queued before publishTopShelf on purpose: publishing starts A7's
        // async `GET /panel/{id}` status fetch. Under the broad "/api/panel/"
        // key that request took this frame (CI run 42528427242); "/frame"
        // only matches frame requests, so the order no longer matters.
        StubURLProtocol.enqueue(.json(#"{"characters":[[63]],"message":"RED","rows":1,"cols":1}"#),
                                for: "/frame")
        let app = AppModel(connection: connection, topShelfStore: store)
        app.publishTopShelf(panels: [panel])
        // Let the status fetch reach the network first, as it did on CI.
        try await Task.sleep(nanoseconds: 300_000_000)
        let panels = PanelsModel(app: app)
        await panels.refreshPreviews(for: [panel])
        let red = try XCTUnwrap(store.items().first)
        let image = try XCTUnwrap(UIImage(data: Data(contentsOf: store.imageURL(for: red))))
        XCTAssertEqual(image.size.width / image.size.height, 16.0 / 9, accuracy: 0.001)
        let slot = TopShelfPreviewRenderer.boardSlot
        // Below the flap's split line, which crosses the slot's centre.
        let pigment = try XCTUnwrap(image.pixel(x: Int(slot.midX), y: Int(slot.midY + 120)))
        XCTAssertEqual(Int(pigment.r), 235, accuracy: 2)
        XCTAssertEqual(Int(pigment.g), 64, accuracy: 2)
        XCTAssertEqual(Int(pigment.b), 52, accuracy: 2)

        StubURLProtocol.enqueue(.json(#"{"characters":[[67]],"message":"BLUE","rows":1,"cols":1}"#),
                                for: "/frame")
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
        // "/frame", not "/api/panel/": an A7 status fetch must not take it.
        StubURLProtocol.enqueue(stub, for: "/frame")
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

    // MARK: A7 — the carousel hero (07b A9 `166:207117`, hero `…;184:181334`)

    /// RGBA bytes of a whole image, for bounding-box scans.
    private struct Pixels {
        let width: Int, height: Int
        let bytes: [UInt8]
        init(_ image: CGImage) throws {
            width = image.width; height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                                  bytesPerRow: width * 4, space: space,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            self.bytes = bytes
        }
        func at(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }
        /// Bounding box (in pixels) of everything brighter than `floor`.
        func box(where test: ((r: Int, g: Int, b: Int)) -> Bool) -> CGRect? {
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            for y in 0..<height { for x in 0..<width where test(at(x, y)) {
                minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
            } }
            return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }

    private func splitFlap() throws -> (Panel, PanelPreview) {
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        var cells = Array(repeating: Array(repeating: BoardCell.blank, count: 30), count: 12)
        let pigments: [BoardColor] = [.red, .orange, .yellow, .green, .blue, .violet]
        for column in 0..<30 {
            cells[1][column] = .color(pigments[column / 5])
            cells[10][column] = .color(pigments[5 - column / 5])
        }
        for (offset, char) in "LIVING ROOM".enumerated() where char != " " { cells[5][9 + offset] = .character(char) }
        return (panel, PanelPreview(rows: 12, cols: 30, cells: cells, message: "LIVING ROOM"))
    }

    /// HIG: the carousel image is the full screen, 1920×1080 pt, supplied
    /// at @1x and @2x.
    func testTheHeroIsFullScreenAtBothScales() throws {
        let (panel, preview) = try splitFlap()
        let hero = try XCTUnwrap(TopShelfPreviewRenderer.hero(panel: panel, preview: preview))
        XCTAssertEqual([hero.oneX.width, hero.oneX.height], [1920, 1080])
        XCTAssertEqual([hero.twoX.width, hero.twoX.height], [3840, 2160])
        let unavailable = try XCTUnwrap(TopShelfPreviewRenderer.unavailableHero)
        XCTAssertEqual([unavailable.oneX.width, unavailable.twoX.width], [1920, 3840])
    }

    /// 07b A9: the board sits in `…;184:183320`'s slot, (700, 11) 1180×678,
    /// right of the system's text column (contextTitle, title, Play / More
    /// Info at x 80–744), on true black.
    func testTheBoardSitsInThe07bHeroSlot() throws {
        XCTAssertEqual(TopShelfPreviewRenderer.boardSlot, CGRect(x: 700, y: 11, width: 1180, height: 678))
        let (panel, preview) = try splitFlap()
        let hero = try XCTUnwrap(TopShelfPreviewRenderer.hero(panel: panel, preview: preview))
        let pixels = try Pixels(hero.oneX)
        let board = try XCTUnwrap(pixels.box { $0.r + $0.g + $0.b > 12 }, "the board must be drawn")
        let slot = TopShelfPreviewRenderer.boardSlot
        XCTAssertTrue(slot.insetBy(dx: -1, dy: -1).contains(board), "\(board) inside \(slot)")
        XCTAssertGreaterThanOrEqual(board.minX, 700, "clear of the text column")
        // Aspect-fit: the board fills the slot on one axis, to within one
        // column: widths and gutters are whole points (FiestaUI
        // board-metrics), so the pitch can't land exactly.
        XCTAssertTrue(abs(board.width - slot.width) <= slot.width / 30 || abs(board.height - slot.height) <= 2, "\(board)")
        XCTAssertEqual(pixels.at(40, 1060).r + pixels.at(40, 1060).g, 0, "true black outside the board")
    }

    /// The golden: the @2x hero, A9 hero `I166:207117;149:182603;184:181334`.
    func testHeroGolden() throws {
        let (panel, preview) = try splitFlap()
        let hero = try XCTUnwrap(TopShelfPreviewRenderer.hero(panel: panel, preview: preview))
        TVSnapshot.assertMatches(UIImage(cgImage: hero.twoX, scale: 2, orientation: .up), named: "top-shelf-hero")
    }

    func testSnapshotsPreserveSquareAndRoundLEDGeometry() throws {
        let preview = PanelPreview(rows: 1, cols: 1, cells: [[.color(.red)]], message: "RED")
        for shape in ["square", "round"] {
            let panel = try MatrixDisplayTests.panel(["render_style": "led_matrix", "device_model_spec": [
                "geometry": ["kind": "pixels", "width": 192, "height": 96],
                "appearance": ["pixelShape": shape, "dotRatio": 0.82]]])
            let hero = try XCTUnwrap(TopShelfPreviewRenderer.hero(panel: panel, preview: preview))
            let attachment = XCTAttachment(image: UIImage(cgImage: hero.oneX))
            attachment.name = "Top Shelf \(shape) LEDs"
            attachment.lifetime = .keepAlways
            add(attachment)
            let pixels = try Pixels(hero.twoX)
            let dot = try XCTUnwrap(pixels.box { $0.r > 200 && $0.g < 120 }, "the red LED must be drawn")
            XCTAssertTrue(TopShelfPreviewRenderer.boardSlot.applying(.init(scaleX: 2, y: 2)).contains(dot))
            let centre = pixels.at(Int(dot.midX), Int(dot.midY))
            XCTAssertGreaterThan(centre.r, 180)
            let corner = pixels.at(Int(dot.minX), Int(dot.minY))
            // The block's top-left pixel is one dot's true corner, antialiased.
            if shape == "square" {
                // DD24: the hub's square is FiestaUI's rounded square: the
                // corner is cut (a square kept it above 150), but by 0.15 of
                // the dot, not into an oval's dark corner.
                XCTAssertLessThan(corner.r, 150, "square LEDs round their true corner (DD24)")
                XCTAssertGreaterThan(corner.r, 60, "…by 0.15 of the dot, not into an oval")
            } else {
                XCTAssertLessThan(corner.r, 40, "round LEDs must retain their dark corners")
            }
        }
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
        let image2x = try Data(contentsOf: try XCTUnwrap(store.imageURL2x(for: item)))
        XCTAssertEqual(image2x, Self.png(try XCTUnwrap(TopShelfPreviewRenderer.unavailableHero?.twoX)),
                       "A7: the @2x artwork is published too")
        XCTAssertEqual(image, Self.png(try XCTUnwrap(TopShelfPreviewRenderer.unavailableHero?.oneX)),
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
