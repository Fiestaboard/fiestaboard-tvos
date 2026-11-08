import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// A5 — layout against the 07b frames, measured from the views' probes
/// (`figmaNode`) as laid out in a real 1920 × 1080 window with the 80/60
/// title-safe area. Every expected number is a node's, read fresh.
@MainActor
final class A5GeometryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FigmaGeometryRegistry.shared.reset()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeApp() async -> AppModel {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.a5.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try? await app.connection.connect(to: URL(string: "http://host:4420")!, displayName: "Maya's FiestaPi")
        return app
    }

    private func frame(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> CGRect {
        try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()[id]?.frame, "no probe for \(id)", file: file, line: line)
    }

    private func assertRect(_ actual: CGRect, x: CGFloat? = nil, y: CGFloat? = nil, width: CGFloat? = nil,
                            height: CGFloat? = nil, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        if let x { XCTAssertEqual(actual.minX, x, accuracy: 1, "\(what) x", file: file, line: line) }
        if let y { XCTAssertEqual(actual.minY, y, accuracy: 1, "\(what) y", file: file, line: line) }
        if let width { XCTAssertEqual(actual.width, width, accuracy: 1, "\(what) width", file: file, line: line) }
        if let height { XCTAssertEqual(actual.height, height, accuracy: 1, "\(what) height", file: file, line: line) }
    }

    // MARK: A3 Panels (`166:147702`)

    static let a3Slot = "I166:147702;149:182603"

    /// One panel that fits this 16:9 TV, nothing set to open at launch: the
    /// card in the left column, the offer in the side slot.
    func testPanelsCardAndOfferSitWhereA3DrawsThem() async throws {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        _ = TVSnapshot.image(PanelsScreen(model: model).environment(app), settle: 0.3)

        assertRect(try frame(Self.a3Slot + ";166:149713"), x: 80, y: 320, width: 800, height: 628,
                   "the panel card (154:4187 Default: 450 preview + 178 meta)")
        assertRect(try frame(Self.a3Slot + ";166:149722"), x: 960, y: 320, width: 800, height: 359,
                   "the open-at-launch offer")
    }

    /// The preview window counts rows by this; it must be the card's height.
    func testCardHeightIsTheA3CardsDefaultHeight() {
        XCTAssertEqual(PanelsScreen.cardHeight(width: 800), 628, accuracy: 0.01)
    }

    // MARK: A1 Connect (`166:147296`)

    func testConnectHubCardAndAddressRowSitWhereA1DrawsThem() async throws {
        let app = await makeApp()
        let model = ConnectModel(app: app)
        let discovery = NeverEndingDiscovery()
        Task { await model.startScan(using: discovery, patience: .seconds(60)) }
        let board = DiscoveredBoard(id: "http://192.168.1.20:4420", name: "FiestaBoard",
                                    host: URL(string: "http://192.168.1.20:4420")!)
        for _ in 0..<300 where model.boards.isEmpty {
            discovery.publish([board])
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        _ = TVSnapshot.image(ConnectScreen(model: model).environment(app), settle: 0.3)
        model.stopScan()

        let slot = "I166:147296;149:182603"
        assertRect(try frame(slot + ";166:147325"), x: 80, y: 340, "the hub card (no focus-lift padding showing)")
        assertRect(try frame(slot + ";166:147344"), x: 80, y: 800, "the address label")
        assertRect(try frame(slot + ";166:147347"), x: 80, y: 850, "the address field")
    }

    // MARK: A2 Device sign-in (`166:147391`)

    func testDeviceSignInBlockFollowsA2sRhythm() async throws {
        let app = await makeApp()
        _ = TVSnapshot.image(DeviceSignInScreen().environment(app), settle: 0.3)

        let slot = "I166:147391;149:182603"
        assertRect(try frame(slot + ";166:147625"), x: 80, y: 320, width: 348, height: 348, "the QR code")
        assertRect(try frame(slot + ";166:147627"), x: 500, y: 320, "the activation address")
        assertRect(try frame(slot + ";166:147655"), x: 80, y: 860, "the buttons row")
    }
}
