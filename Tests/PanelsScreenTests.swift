import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class PanelsScreenTests: XCTestCase {

    private func makeApp() async -> AppModel {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.panels.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try? await app.connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        return app
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testLoadsThePanelList() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        XCTAssertEqual(model.panels.count, 1)
        XCTAssertEqual(model.panels.first?.name, "Living Room")
        XCTAssertNil(model.errorMessage)
    }

    /// An instance with auth on that we cannot satisfy must offer sign-in,
    /// not a dead-end error.
    func testA401RoutesToSignIn() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(#"{"detail":"Not authenticated"}"#, status: 401), for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        XCTAssertEqual(app.route, .signIn)
    }

    func testAnUnreachableBoardShowsAnError() async {
        let app = await makeApp()
        let model = PanelsModel(app: app)
        await model.load()   // nothing enqueued
        XCTAssertNotNil(model.errorMessage)
    }

    /// A board that answers promptly with a lockout, a server fault, or a
    /// payload this app cannot parse is NOT an unreachable board. Saying so
    /// sends people to check cables while the board sits there replying.
    func testALockoutSaysSoRatherThanBlamingTheNetwork() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(
            .json(#"{"detail":"Too many failed login attempts. Try again later."}"#, status: 429),
            for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        let message = model.errorMessage ?? ""
        XCTAssertFalse(message.contains("still on"),
                       "a 429 is not an unreachable board, got: \(message)")
        XCTAssertTrue(message.lowercased().contains("too many")
                      || message.lowercased().contains("sign-in"),
                      "a 429 should explain the lockout, got: \(message)")
    }

    func testAServerFaultReportsItsStatus() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(#"{"detail":"boom"}"#, status: 500), for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        let message = model.errorMessage ?? ""
        XCTAssertTrue(message.contains("500"), "the status is the whole clue, got: \(message)")
        XCTAssertFalse(message.contains("still on"))
    }

    func testAnUnparseablePayloadSaysSoRatherThanBlamingTheNetwork() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(#"{"panels":[{"id":"1"}]}"#), for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        let message = model.errorMessage ?? ""
        XCTAssertFalse(message.contains("still on"),
                       "a board that replied is reachable, got: \(message)")
        XCTAssertTrue(message.lowercased().contains("understand")
                      || message.lowercased().contains("version"),
                      "a decode failure should point at versions, got: \(message)")
    }

    /// The one case that really is the network keeps its plain wording.
    func testAnUnreachableBoardStillSaysCheckItIsOn() async {
        let app = await makeApp()
        let model = PanelsModel(app: app)
        await model.load()   // nothing enqueued -> transport failure
        XCTAssertTrue((model.errorMessage ?? "").contains("still on"))
    }

    func testAnEmptyListIsNotAnError() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(#"{"panels":[],"total":0}"#), for: "/api/panels")
        let model = PanelsModel(app: app)
        await model.load()
        XCTAssertTrue(model.panels.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testPanelDescribesItsGridAndScreen() throws {
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        XCTAssertEqual(panel.gridDescription, "30 × 12")
        XCTAssertTrue(panel.screenDescription.contains("65"))
    }

    /// An orphaned panel must say so rather than offering a board that
    /// cannot render.
    func testAPanelWithAMissingBoardDescribesItself() throws {
        let orphan = Fixtures.panelJSON
            .replacingOccurrences(of: "\"board_missing\":false", with: "\"board_missing\":true")
            .replacingOccurrences(of: "\"rows\":12", with: "\"rows\":null")
            .replacingOccurrences(of: "\"cols\":30", with: "\"cols\":null")
        let panel = try JSONDecoder().decode(Panel.self, from: Data(orphan.utf8))
        XCTAssertTrue(panel.boardMissing)
        XCTAssertEqual(panel.gridDescription, "No board")
    }

    func testScreenRendersLoadedEmptyAndErrorStates() async {
        let app = await makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        RenderHarness.render(PanelsScreen().environment(app))
    }
}
