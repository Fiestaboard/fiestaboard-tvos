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

        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
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
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
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

    func testTopShelfLinkOpensItsPanelOnlyForAConnectedBoard() async throws {
        let model = makeModel()
        let link = URL(string: "fiestaboard://panel/abc123def456")!
        model.openTopShelfURL(link)
        XCTAssertEqual(model.route, .connecting)

        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await model.connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        model.openTopShelfURL(link)
        XCTAssertEqual(model.route, .viewer("abc123def456"))
        model.start()
        XCTAssertEqual(model.route, .viewer("abc123def456"),
                       "a cold launch must not replace the Top Shelf destination")
        model.openTopShelfURL(URL(string: "https://example.com/panel/other")!)
        XCTAssertEqual(model.route, .viewer("abc123def456"))
    }

    func testRootReappearanceDoesNotReopenAnOldTopShelfPanel() async throws {
        let model = makeModel()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await model.connection.connect(to: URL(string: "http://host:4420")!,
                                               displayName: "Board")
        model.start()
        model.openTopShelfURL(URL(string: "fiestaboard://panel/abc123def456")!)
        model.showPanels()

        model.start()

        XCTAssertEqual(model.route, .panels,
                       "returning to the app should keep the screen the viewer left open")
    }

    func testDisconnectClearsOnlyThisAppsTopShelfCache() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("topshelf-disconnect-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        try store.replace([.init(panelID: "one", name: "Kitchen", imageData: Data([1]))])
        let model = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore()), topShelfStore: store)

        model.disconnect()
        XCTAssertTrue(store.items().isEmpty)
    }

    func testDefaultViewerLaunchAlsoRefreshesTopShelfPreviews() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("topshelf-default-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        let connection = ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        connection.setDefaultPanel(ref: "abc123def456")
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/api/panel/")
        let model = AppModel(connection: connection, topShelfStore: store)

        model.start()
        XCTAssertEqual(model.route, .viewer("abc123def456"))
        for _ in 0..<40 where store.items().isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(store.items().map(\.panelID), ["abc123def456"])
    }

    func testRootViewRendersEveryRoute() {
        for route in [Route.connecting, .connect, .signIn, .panels, .viewer("1"), .settings] {
            let model = makeModel()
            model.route = route
            RenderHarness.render(RootView().environment(model))
        }
    }

    /// Settings is reached from two places and tvOS has one Back button for
    /// both. Leaving it must return to the caller — Menu used to fall
    /// through to the system and quit the app.
    @MainActor
    func testLeavingSettingsReturnsToTheViewerItWasOpenedFrom() {
        let model = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore()))
        model.route = .viewer("abc123def456")

        model.showSettings()
        XCTAssertEqual(model.route, .settings)

        model.dismissSettings()
        XCTAssertEqual(model.route, .viewer("abc123def456"))
    }

    @MainActor
    func testLeavingSettingsOpenedFromTheListReturnsToTheList() {
        let model = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore()))
        model.route = .panels

        model.showSettings()
        model.dismissSettings()
        XCTAssertEqual(model.route, .panels)
    }

    /// Reopening Settings must not overwrite the origin with Settings itself.
    @MainActor
    func testReopeningSettingsKeepsTheOriginalOrigin() {
        let model = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore()))
        model.route = .viewer("one")

        model.showSettings()
        model.showSettings()
        model.dismissSettings()
        XCTAssertEqual(model.route, .viewer("one"))
    }
}
