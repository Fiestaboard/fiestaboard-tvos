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
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        await model.connect(to: board.host, name: board.name)
        XCTAssertEqual(app.route, .panels)
    }

    func testConnectingToALockedBoardRoutesToSignIn() async {
        let app = makeApp()
        let model = ConnectModel(app: app)
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
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
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
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

    // MARK: Board labels

    /// The hostname alone is the label when it is unambiguous — short enough
    /// to read from the sofa.
    func testBoardAddressUsesJustTheHostWhenItIsUnambiguous() {
        let other = DiscoveredBoard(id: "http://192.168.1.51:4420",
                                    name: "Kitchen",
                                    host: URL(string: "http://192.168.1.51:4420")!)
        XCTAssertEqual(BoardAddressLabel.text(for: board, among: [board, other]), "192.168.1.50")
    }

    /// Two instances on one Pi differ only by port, so the port has to show
    /// or the two cards are indistinguishable.
    func testBoardAddressIncludesThePortWhenTwoBoardsShareAHost() {
        let second = DiscoveredBoard(id: "http://192.168.1.50:4421",
                                     name: "Garage",
                                     host: URL(string: "http://192.168.1.50:4421")!)
        let found = [board, second]
        XCTAssertEqual(BoardAddressLabel.text(for: board, among: found), "192.168.1.50:4420")
        XCTAssertEqual(BoardAddressLabel.text(for: second, among: found), "192.168.1.50:4421")
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

    func testDiscoveredBoardCardRenders() {
        RenderHarness.render(DiscoveredBoardCard(board: board, address: "192.168.1.50") {})
    }

    func testSignInCanForgetAndChooseAnotherBoard() async throws {
        let app = makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        _ = try await app.connection.connect(to: URL(string: "http://board.local:4420")!, displayName: "Old board")
        app.route = .signIn

        SignInModel(app: app).useAnotherBoard()
        XCTAssertEqual(app.route, .connect)
        XCTAssertNil(app.connection.saved)
    }

    func testSignInWithBadCredentialsShowsAnErrorAndStays() async {
        let app = makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        _ = try? await app.connection.connect(to: board.host, displayName: "Board")
        app.route = .signIn

        StubURLProtocol.enqueue(.json(#"{"detail":"Invalid username or password"}"#, status: 401),
                                for: "/api/auth/login")
        let model = SignInModel(app: app)
        model.username = "jeffre"
        model.password = "wrong"
        await model.submit()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(app.route, .signIn)
    }

    func testSuccessfulSignInRoutesToPanels() async {
        let app = makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        _ = try? await app.connection.connect(to: board.host, displayName: "Board")

        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")
        let model = SignInModel(app: app)
        model.username = "jeffre"
        model.password = "hunter2"
        await model.submit()

        XCTAssertEqual(app.route, .panels)
        XCTAssertNil(model.errorMessage)
    }

    /// Menu on sign in goes back to choosing a board — it must not quit the
    /// app, and it must not throw the saved board away the way
    /// "Use another board" deliberately does.
    func testSignInBackReturnsToConnectWithoutForgettingTheBoard() async throws {
        let app = makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        _ = try await app.connection.connect(to: board.host, displayName: "Board")
        app.route = .signIn

        SignInModel(app: app).back()

        XCTAssertEqual(app.route, .connect)
        XCTAssertNotNil(app.connection.saved, "Back is a reflex; it must not forget the board")
    }

}
