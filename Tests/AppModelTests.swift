import SwiftUI
import UIKit
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
    override func tearDown() {
        StubURLProtocol.reset()
        // Rendering the viewer route touches the real flag; leave the test
        // host's display the way we found it.
        UIApplication.shared.isIdleTimerDisabled = false
        super.tearDown()
    }

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

    // MARK: Keeping a wall-mounted board awake

    /// Record what the app asks of the idle timer, without touching the
    /// test host's real display.
    private func watchScreenAwake(_ model: AppModel) -> NSMutableArray {
        let log = NSMutableArray()
        model.screenAwake.sink = { held in log.add(held) }
        model.applyScreenAwake()
        log.removeAllObjects()
        return log
    }

    func testTheScreenIsHeldAwakeOnlyWhileABoardIsShowing() {
        let model = makeModel()
        _ = watchScreenAwake(model)

        model.openPanel(ref: "abc123def456")
        XCTAssertTrue(model.screenAwake.isHeld, "a board on a wall must not be put to sleep")

        model.showSettings()
        XCTAssertFalse(model.screenAwake.isHeld, "off the board, the TV's own sleep settings rule")

        model.dismissSettings()
        XCTAssertTrue(model.screenAwake.isHeld, "back on the board, hold it awake again")

        model.showPanels()
        XCTAssertFalse(model.screenAwake.isHeld)
    }

    /// The reason this moved out of `ViewerScreen`: `onAppear` and
    /// `onDisappear` are not ordered against each other across a route
    /// swap, so the flag could be left cleared by the screen that was
    /// leaving while the board was already back up. Driven by the route,
    /// there is no ordering left to get wrong.
    func testARouteRoundTripLeavesTheScreenHeldAwake() {
        let model = makeModel()
        let log = watchScreenAwake(model)
        model.openPanel(ref: "abc123def456")

        for _ in 0..<5 {
            model.showSettings()
            model.dismissSettings()
            model.showPanels()
            model.openPanel(ref: "abc123def456")
        }

        XCTAssertTrue(model.screenAwake.isHeld)
        XCTAssertEqual(log.lastObject as? Bool, true,
                       "the last thing said to the idle timer must match the screen on show")
    }

    /// A wake request is not a fact the system keeps for us. Coming back to
    /// the foreground, the app says it again.
    func testReturningToTheForegroundRestatesTheWakeRequest() {
        let model = makeModel()
        let log = watchScreenAwake(model)
        model.openPanel(ref: "abc123def456")
        log.removeAllObjects()

        model.screenAwake.onForeground?()

        XCTAssertEqual(log as! [Bool], [true])
    }

    func testAColdLaunchStraightIntoABoardHoldsTheScreenAwake() async throws {
        let connection = ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        connection.setDefaultPanel(ref: "abc123def456")

        let model = AppModel(connection: connection)
        model.screenAwake.sink = { _ in }
        model.start()

        XCTAssertEqual(model.route, .viewer("abc123def456"))
        XCTAssertTrue(model.screenAwake.isHeld)
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
