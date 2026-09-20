import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// Yields a fixed list so screen tests never touch the network.
final class StubDiscovery: BoardDiscovering {
    private let items: [DiscoveredBoard]
    private(set) var stopped = false

    init(boards: [DiscoveredBoard]) { self.items = boards }

    func boards() -> AsyncStream<[DiscoveredBoard]> {
        AsyncStream { continuation in
            continuation.yield(items)
            continuation.finish()
        }
    }

    func stop() { stopped = true }
}

@MainActor
final class ConnectScreenTests: XCTestCase {

    private let board = DiscoveredBoard(id: "http://192.168.1.50:4420",
                                        name: "FiestaBoard",
                                        host: URL(string: "http://192.168.1.50:4420")!)

    private func makeApp() -> AppModel {
        AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.connect.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    func testScanningPublishesDiscoveredBoards() async {
        let model = ConnectModel(app: makeApp())
        let discovery = StubDiscovery(boards: [board])
        await model.startScan(using: discovery)
        XCTAssertEqual(model.boards, [board])
    }

    func testConnectingToAnOpenBoardRoutesToPanels() async {
        let app = makeApp()
        let model = ConnectModel(app: app)
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        await model.connect(to: board.host, name: board.name)
        XCTAssertEqual(app.route, .panels)
    }

    func testConnectingToALockedBoardRoutesToSignIn() async {
        let app = makeApp()
        let model = ConnectModel(app: app)
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
        await model.connect(to: board.host, name: board.name)
        XCTAssertEqual(app.route, .signIn)
    }

    /// An unreachable address must say so rather than silently do nothing.
    func testAnUnreachableAddressReportsAnError() async {
        let app = makeApp()
        let model = ConnectModel(app: app)
        // Nothing enqueued: the request fails at the transport.
        await model.connect(to: board.host, name: board.name)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(app.route, .connecting, "a failed connect must not navigate")
    }

    func testManualEntryNormalisesABareIP() async {
        let app = makeApp()
        let model = ConnectModel(app: app)
        model.manualAddress = "192.168.1.50"
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        await model.connectManually()
        XCTAssertEqual(app.connection.saved?.host.absoluteString, "http://192.168.1.50:4420")
    }

    func testBlankManualEntryIsRejectedWithoutARequest() async {
        let model = ConnectModel(app: makeApp())
        model.manualAddress = "   "
        await model.connectManually()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testStopScanStopsDiscovery() async {
        let model = ConnectModel(app: makeApp())
        let discovery = StubDiscovery(boards: [board])
        await model.startScan(using: discovery)
        model.stopScan()
        XCTAssertTrue(discovery.stopped)
    }

    // MARK: Rendering

    func testConnectScreenRendersInEveryState() {
        let app = makeApp()
        RenderHarness.render(ConnectScreen().environment(app))

        let withError = makeApp()
        withError.errorMessage = "This FiestaBoard has no account yet."
        RenderHarness.render(ConnectScreen().environment(withError))
    }

    func testSignInScreenRenders() {
        RenderHarness.render(SignInScreen().environment(makeApp()))
    }

    func testSignInWithBadCredentialsShowsAnErrorAndStays() async {
        let app = makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
        _ = try? await app.connection.connect(to: board.host, displayName: "Board")
        app.route = .signIn

        StubURLProtocol.enqueue(.json(#"{"detail":"Invalid username or password"}"#, status: 401),
                                for: "/auth/login")
        let model = SignInModel(app: app)
        model.username = "jeffre"
        model.password = "wrong"
        await model.submit()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(app.route, .signIn)
    }

    func testSuccessfulSignInRoutesToPanels() async {
        let app = makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
        _ = try? await app.connection.connect(to: board.host, displayName: "Board")

        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/auth/login")
        let model = SignInModel(app: app)
        model.username = "jeffre"
        model.password = "hunter2"
        await model.submit()

        XCTAssertEqual(app.route, .panels)
        XCTAssertNil(model.errorMessage)
    }
}
