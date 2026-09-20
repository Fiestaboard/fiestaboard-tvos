import SwiftUI
import XCTest
@testable import FiestaBoardTV

@MainActor
final class AppModelTests: XCTestCase {

    private func makeModel(defaults: UserDefaults? = nil) -> AppModel {
        let suite = defaults ?? UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!
        let connection = ConnectionStore(
            defaults: suite,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        return AppModel(connection: connection)
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testWithNoSavedBoardItAsksToConnect() {
        let model = makeModel()
        model.start()
        XCTAssertEqual(model.route, .connect)
    }

    /// The payoff of the whole app: a configured TV powers on into its board.
    func testWithADefaultPanelItOpensStraightIntoTheViewer() async throws {
        let defaults = UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!
        let credentials = InMemoryCredentialStore()
        let connection = ConnectionStore(
            defaults: defaults, credentials: credentials,
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })

        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        connection.setDefaultPanel(ref: "1")

        let model = AppModel(connection: connection)
        model.start()
        XCTAssertEqual(model.route, .viewer("1"))
    }

    func testASavedBoardWithNoDefaultPanelLandsOnTheList() async throws {
        let defaults = UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!
        let connection = ConnectionStore(
            defaults: defaults, credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")

        let model = AppModel(connection: connection)
        model.start()
        XCTAssertEqual(model.route, .panels)
    }

    func testConnectResultsRouteCorrectly() {
        let model = makeModel()
        model.finishConnect(.ready)
        XCTAssertEqual(model.route, .panels)

        model.finishConnect(.needsSignIn)
        XCTAssertEqual(model.route, .signIn)

        model.finishConnect(.needsSetup)
        XCTAssertEqual(model.route, .connect)
        XCTAssertNotNil(model.errorMessage, "setup-required must explain itself")
    }

    func testNavigationBetweenScreens() {
        let model = makeModel()
        model.openPanel(ref: "abc")
        XCTAssertEqual(model.route, .viewer("abc"))
        model.showPanels()
        XCTAssertEqual(model.route, .panels)
        model.showSettings()
        XCTAssertEqual(model.route, .settings)
    }

    func testRootViewRendersEveryRoute() {
        for route in [Route.connecting, .connect, .signIn, .panels, .viewer("1"), .settings] {
            let model = makeModel()
            model.route = route
            RenderHarness.render(RootView().environment(model))
        }
    }
}
