import Observation
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

    /// A board that has been powered on but has never had an account made
    /// on it. `Fixtures` has no such status, and it belongs to another file.
    private static let authStatusSetupRequired = """
    {"enabled":true,"setup_required":true,"authenticated":false,
     "username":null,"mode":"enabled","first_run":true}
    """

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

        // And the banner must not outlive the state it describes: the retry
        // that works is the one still showing the last attempt's complaint.
        model.finishConnect(.ready)
        XCTAssertNil(model.errorMessage)
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

    func testSettingsKeepsTheViewedPanelAsItsEditingContext() {
        let model = makeModel()
        model.openPanel(ref: "7")
        model.showSettings()
        XCTAssertEqual(model.settingsPanelRef, "7")
        model.showSettings()
        XCTAssertEqual(model.settingsPanelRef, "7")
        model.dismissSettings()
        XCTAssertNil(model.settingsPanelRef)
        model.showPanels()
        model.showSettings()
        XCTAssertNil(model.settingsPanelRef, "the panel list must not inherit an old viewer's editing context")
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
        // One clause of the guard each, so no rejection can be credited to
        // the wrong check. `https://example.com/panel/other` stood here
        // alone, and it fails the one-component count by itself — the scheme
        // and host checks could both have been deleted with this still green.
        for rejected in ["https://panel/abc123def456",         // scheme
                         "fiestaboard://sofa/abc123def456",    // host
                         "fiestaboard://panel/abc123/def456",  // two components
                         "fiestaboard://panel"] {              // none at all
            model.openTopShelfURL(URL(string: rejected)!)
            XCTAssertEqual(model.route, .viewer("abc123def456"), rejected)
        }
    }

    /// The carousel outlives the session it was built from. Home keeps
    /// vending an item after someone signs out of the board, and the link it
    /// sends must not walk straight past the sign-in screen into a panel this
    /// TV is no longer allowed to read. Nothing entered that clause.
    func testATopShelfLinkIsRefusedOnceTheBoardIsSignedOutOf() async throws {
        let model = makeModel()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        _ = try await model.connection.connect(to: URL(string: "http://host:4420")!,
                                               displayName: "Board")
        model.connection.signOut()
        model.start()
        XCTAssertEqual(model.route, .signIn, "the test must begin signed out")

        model.openTopShelfURL(URL(string: "fiestaboard://panel/abc123def456")!)

        XCTAssertEqual(model.route, .signIn)
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

    /// The cold launch is the worst way into hazard 8, and the reason it hid
    /// for so long. `start()` sends a TV that has a default panel straight to
    /// `.viewer("a")`, so the viewer and its `@State` model are already built
    /// when Home hands over the URL for a *different* panel a runloop turn
    /// later. A TV with no default panel was sitting on `.panels` with no
    /// viewer yet, so its jump worked, and the bug looked like nothing.
    ///
    /// Two halves, and only one of them is visible from this layer.
    ///
    /// This one: the route has to end on "b", and the move has to be
    /// *published*. `AppModel.route` is hand-written around `withMutation`,
    /// and a setter that dropped it would still satisfy an equality check
    /// while telling SwiftUI nothing — `RootView` would never re-evaluate,
    /// `ViewerScreen`'s `ref` would never change, and its `.onChange(of:)`
    /// teardown could not fire. That is the same wrong board on the wall,
    /// reached from this file's side, so asserting the route alone would
    /// repeat the shape of the assertion that missed the bug the first time.
    ///
    /// The other half — that on being told, the screen stops the old model
    /// and binds a new one on "b" — is not observable here: `RootView` builds
    /// `ViewerScreen(ref:)` with no seam onto the model it makes.
    /// `ViewerScreenTests.testChangingTheRefRebindsTheModelToTheNewPanel`
    /// drives that through a real SwiftUI update and is the real guard for
    /// it. Revert the `.onChange(of: ref)` in `ViewerScreen` and that test
    /// fails; this one stays green.
    func testAColdLaunchIntoItsDefaultPanelStillFollowsALinkToAnother() async throws {
        let connection = ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        connection.setDefaultPanel(ref: "aaa111aaa111")

        let model = AppModel(connection: connection)
        model.screenAwake.sink = { _ in }
        model.start()
        XCTAssertEqual(model.route, .viewer("aaa111aaa111"),
                       "the viewer has to be up on the default panel before the link arrives")

        let published = expectation(description: "the route change reaches the view layer")
        withObservationTracking({ _ = model.route }, onChange: { published.fulfill() })

        model.openTopShelfURL(URL(string: "fiestaboard://panel/bbb222bbb222")!)

        XCTAssertEqual(model.route, .viewer("bbb222bbb222"),
                       "a default panel must not swallow the carousel's destination")
        await fulfillment(of: [published], timeout: 1)
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

    /// The store lives in the group container's `Library/Caches` — the only
    /// place on tvOS the app is allowed to write, and a place the system may
    /// purge whenever it likes. So what was published last week is not
    /// something the app gets to assume is still there.
    func testReturningToTheForegroundRepublishesTheCarousel() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("topshelf-foreground-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        let connection = ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        let model = AppModel(connection: connection, topShelfStore: store)
        model.screenAwake.sink = { _ in }

        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        model.screenAwake.onForeground?()

        for _ in 0..<40 where store.items().isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(store.items().map(\.panelID), ["abc123def456"],
                       "a purged cache has to be rewritten when the app comes back")
    }

    /// A list the caller already holds needs no second fetch — this is the
    /// entry point the panel list calls, and it is how a TV whose owner never
    /// sets a default panel gets a carousel at all.
    func testPublishingFromALoadedPanelListAsksTheBoardForNothing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("topshelf-list-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TopShelfSnapshotStore(directory: directory)
        let connection = ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://host:4420")!, displayName: "Board")
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        let model = AppModel(connection: connection, topShelfStore: store)
        StubURLProtocol.reset()

        model.publishTopShelf(panels: [panel])

        XCTAssertEqual(store.items().map(\.panelID), [panel.id])
        XCTAssertTrue(StubURLProtocol.requests.isEmpty,
                      "made \(StubURLProtocol.requests)")
    }

    // MARK: A board that still needs its first account

    /// It used to be written to disk before the check, so the next cold
    /// launch found a saved board, routed to Panels, and got 409 over an
    /// empty grid with no control leading back to Connect. Recovery was
    /// deleting the app — on the *first run* of a brand-new board.
    func testABoardNeedingSetupIsNotRememberedAndTheNextLaunchReturnsToConnect() async throws {
        let defaults = UserDefaults(suiteName: "tv.app.\(UUID().uuidString)")!
        let credentials = InMemoryCredentialStore()
        let makeClient: (URL) -> FiestaClient = {
            FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession())
        }
        let connection = ConnectionStore(defaults: defaults, credentials: credentials,
                                         clientFactory: makeClient)
        StubURLProtocol.enqueue(.json(Self.authStatusSetupRequired), for: "/api/auth/status")

        let result = try await connection.connect(to: URL(string: "http://host:4420")!,
                                                  displayName: "Board")

        XCTAssertEqual(result, .needsSetup)
        XCTAssertNil(connection.saved, "an unprovisioned board must not be remembered")
        XCTAssertNil(connection.client)

        let relaunched = AppModel(connection: ConnectionStore(defaults: defaults,
                                                              credentials: credentials,
                                                              clientFactory: makeClient))
        relaunched.screenAwake.sink = { _ in }
        relaunched.start()
        XCTAssertEqual(relaunched.route, .connect)
    }

    /// The old copy told someone standing inside FiestaBoard to go and finish
    /// setup "in the FiestaBoard app". The account can only be made on the
    /// board's own web page, so that is what it has to say.
    func testTheSetupRequiredMessageNamesTheBrowserRatherThanThisApp() throws {
        let model = makeModel()
        model.finishConnect(.needsSetup)

        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertFalse(message.contains("in the FiestaBoard app"),
                       "this IS the FiestaBoard app: \(message)")
        XCTAssertTrue(message.contains("browser"), message)
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
