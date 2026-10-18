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

/// Yields once and then never finishes — which is what `BonjourDiscovery`
/// does for as long as a browse is running. `StubDiscovery` finishes the
/// moment it is asked, so it cannot see a scan that has no terminal state.
final class NeverEndingDiscovery: BoardDiscovering {
    private(set) var stopped = false
    private var continuation: AsyncStream<[DiscoveredBoard]>.Continuation?

    func boards() -> AsyncStream<[DiscoveredBoard]> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield([])
        }
    }

    /// Delivers a board late, the way one powered on mid-scan arrives.
    func publish(_ boards: [DiscoveredBoard]) { continuation?.yield(boards) }

    func stop() {
        stopped = true
        continuation?.finish()
    }
}

@MainActor
final class ConnectScreenTests: XCTestCase {

    private let board = DiscoveredBoard(id: "http://192.168.1.50:4420",
                                        name: "FiestaBoard",
                                        host: URL(string: "http://192.168.1.50:4420")!)

    /// A second card on screen, so "the marker is set" can be told apart
    /// from "the marker is set to the board that was actually pressed".
    private let second = DiscoveredBoard(id: "http://192.168.1.51:4420",
                                         name: "Garage",
                                         host: URL(string: "http://192.168.1.51:4420")!)

    private func makeApp() -> AppModel {
        AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.connect.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    /// Polls rather than sleeping a fixed span: the machine running this is
    /// not always idle.
    ///
    /// Fails on fall-through rather than returning. Running out of attempts
    /// used to cost three seconds and then pass in silence, which is how a
    /// condition that never comes true reads as "flaky" instead of "wrong" —
    /// the exact shape this suite exists to catch. `file` and `line` default
    /// to the caller's so the failure lands on the test that was waiting
    /// rather than on this helper, where it says nothing.
    private func settle(until description: String,
                        file: StaticString = #file,
                        line: UInt = #line,
                        _ condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out after 3s waiting for \(description)", file: file, line: line)
    }

    /// A patience window wide enough that it cannot close part-way through a
    /// test. Ten milliseconds — what the `foundNothing` tests below use on
    /// purpose — expires while the test is still setting up, so anything that
    /// then asserts `.looking` is racing the window rather than stating
    /// something. Nothing waits this out: every test using it tears the scan
    /// down, which cancels the window.
    private static let patienceThatOutlastsTheTest: Duration = .seconds(30)

    func testScanningPublishesDiscoveredBoards() async {
        let model = ConnectModel(app: makeApp())
        let discovery = StubDiscovery(boards: [board])
        await model.startScan(using: discovery)
        XCTAssertEqual(model.boards, [board])
    }

    /// The screen exists before its first scan does: `.onAppear`'s task is a
    /// hop behind the model that `.onAppear` built. That window used to read
    /// as "scanned, found nothing" — two independent booleans, both false —
    /// and painted "No FiestaBoard on this network yet" on the first screen
    /// App Review sees, before a single packet had gone out.
    func testAModelWhoseScanHasNotStartedIsNotTheTerminalEmptyState() {
        let model = ConnectModel(app: makeApp())

        XCTAssertEqual(model.scanState, .idle)
        XCTAssertTrue(model.scanState.promisesABoardIsComing,
                      "a scan that has not started must not render as one that found nothing")
    }

    /// Re-entering Connect from Sign In, or after Forget, comes through a
    /// `stopScan` — the other way into the same window.
    func testATornDownScanIsNotTheTerminalEmptyStateEither() {
        let model = ConnectModel(app: makeApp())
        model.stopScan()

        XCTAssertEqual(model.scanState, .idle)
        XCTAssertTrue(model.scanState.promisesABoardIsComing)
    }

    /// The one state that earns the terminal copy, and the only one.
    func testOnlyAScanThatListenedLongEnoughEarnsTheTerminalCopy() {
        XCTAssertTrue(ConnectModel.ScanState.looking.promisesABoardIsComing)
        XCTAssertFalse(ConnectModel.ScanState.foundNothing.promisesABoardIsComing)
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
        // Nothing answered at all: that one really is the network, and the
        // fallback message is the only one that names the address typed.
        XCTAssertEqual(model.errorMessage?.contains("192.168.1.50"), true)
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

    /// The screen used to sit under "this takes a few seconds" forever,
    /// because the only thing that ended the scan was the scan being stopped.
    func testAnEndlessScanEventuallyAdmitsItHasFoundNothing() async {
        let model = ConnectModel(app: makeApp())
        let discovery = NeverEndingDiscovery()
        let scan = Task { await model.startScan(using: discovery, patience: .milliseconds(10)) }
        await settle(until: "the patience window to close") { model.scanState == .foundNothing }

        XCTAssertEqual(model.scanState, .foundNothing)
        XCTAssertFalse(discovery.stopped,
                       "the browse keeps running: a board powered on at second 20 must still appear")

        model.stopScan()
        XCTAssertEqual(model.scanState, .idle)
        XCTAssertTrue(discovery.stopped)
        await scan.value
    }

    /// The patience window is not a timeout. It only stops the screen
    /// promising a board is coming; the browse behind it is untouched.
    func testABoardFoundAfterThePatienceWindowStillArrives() async {
        let model = ConnectModel(app: makeApp())
        let discovery = NeverEndingDiscovery()
        let scan = Task { await model.startScan(using: discovery, patience: .milliseconds(10)) }
        await settle(until: "the patience window to close") { model.scanState == .foundNothing }

        discovery.publish([board])
        await settle(until: "the late board to land") { !model.boards.isEmpty }

        XCTAssertEqual(model.boards, [board])
        XCTAssertEqual(model.scanState, .looking,
                       "a board arriving late puts the screen back to showing a list")

        model.stopScan()
        await scan.value
    }

    /// `.onAppear` can fire twice for one screen. A second browse would run
    /// behind the first and only the newer one would ever be stopped.
    func testASecondScanIsRejectedWhileOneIsRunning() async {
        let model = ConnectModel(app: makeApp())
        let running = NeverEndingDiscovery()
        let scan = Task { await model.startScan(using: running,
                                                patience: Self.patienceThatOutlastsTheTest) }
        await settle(until: "the browse to start looking") { model.scanState == .looking }

        let second = StubDiscovery(boards: [board])
        await model.startScan(using: second)

        XCTAssertTrue(model.boards.isEmpty, "the second discovery must not be adopted")
        XCTAssertTrue(second.stopped, "and it must not be left running either")

        model.stopScan()
        await scan.value
    }

    /// `.needsSetup` routes to Connect — the screen you are already on — so
    /// `.onAppear` never fires again. Stopping discovery there left the app
    /// with no browser for the rest of its life.
    func testABoardThatNeedsSetupLeavesDiscoveryRunning() async {
        let app = makeApp()
        let model = ConnectModel(app: app)
        let discovery = NeverEndingDiscovery()
        // The window has to outlast the connect below: were it to close while
        // the request is on the wire, the `.looking` assertion would be about
        // the window rather than about discovery still being alive.
        let scan = Task { await model.startScan(using: discovery,
                                                patience: Self.patienceThatOutlastsTheTest) }
        await settle(until: "the browse to start looking") { model.scanState == .looking }

        StubURLProtocol.enqueue(.json(Self.authStatusSetupRequired), for: "/api/auth/status")
        await model.connect(to: board.host, name: board.name)

        XCTAssertFalse(discovery.stopped,
                       "a board that needs its first account must not kill discovery")
        XCTAssertEqual(model.scanState, .looking)

        model.stopScan()
        await scan.value
    }

    /// Every other success is a departure from this screen, so the browse
    /// should stop with it.
    func testAConnectThatLeavesTheScreenStopsDiscovery() async {
        let app = makeApp()
        let model = ConnectModel(app: app)
        let discovery = NeverEndingDiscovery()
        let scan = Task { await model.startScan(using: discovery,
                                                patience: Self.patienceThatOutlastsTheTest) }
        await settle(until: "the browse to start looking") { model.scanState == .looking }

        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        await model.connect(to: board.host, name: board.name)

        XCTAssertTrue(discovery.stopped)
        XCTAssertEqual(app.route, .panels)
        await scan.value
    }

    private static let authStatusSetupRequired = """
    {"enabled":true,"setup_required":true,"authenticated":false,
     "username":null,"mode":"enabled","first_run":true}
    """

    // MARK: Errors

    /// A board that answered is not an unreachable board. Saying so sends
    /// people to check cables while it sits there replying.
    func testABoardThatAnswersAnErrorIsNotBlamedOnTheNetwork() async {
        let model = ConnectModel(app: makeApp())
        StubURLProtocol.enqueue(.json(#"{"detail":"boom"}"#, status: 500), for: "/api/auth/status")
        await model.connect(to: board.host, name: board.name)

        XCTAssertEqual(model.errorMessage, FiestaError.http(500).userMessage)
        XCTAssertFalse(model.errorMessage?.contains("Couldn't reach") ?? true)
    }

    /// `app.errorMessage` is cleared only by transitions that never happen
    /// while you stay on Connect, so one unprovisioned board used to explain
    /// every later failure for the rest of the session.
    func testAFreshAttemptClearsTheStaleAppLevelError() async {
        let app = makeApp()
        app.errorMessage = "This FiestaBoard has no account yet."
        let model = ConnectModel(app: app)

        await model.connect(to: board.host, name: board.name)

        XCTAssertNil(app.errorMessage)
        XCTAssertNotNil(model.errorMessage)
    }

    // MARK: The mark a press leaves

    /// The press has to leave a mark on the card, and on the card that was
    /// pressed: `authStatus()` then `login()` is two ten-second timeouts on a
    /// board that has gone off, so without the marker the screen sits
    /// completely unchanged for twenty seconds and reads as broken.
    ///
    /// Asserted *during* the attempt on purpose. This used to check only that
    /// the marker gets cleared afterwards, which is the half that was never
    /// broken — deleting the line that sets it left the suite green.
    ///
    /// The attempt is held open the way the settings suite holds a save open:
    /// the task runs up to its first real suspension, which is the request
    /// itself, and `Task.yield()` hands control back with it still in flight.
    func testTheConnectingMarkerNamesThePressedBoardWhileTheAttemptRuns() async {
        let model = ConnectModel(app: makeApp())
        model.boards = [board, second]

        // Nothing enqueued, so the request fails — but not before it is sent.
        let connecting = Task { await model.connect(to: second.host, name: second.name) }
        await Task.yield()

        XCTAssertTrue(model.isConnecting)
        XCTAssertEqual(model.connectingBoardID, second.id)
        XCTAssertTrue(model.connectInFlight(for: second.id),
                      "the pressed card has to show it took the press")
        XCTAssertFalse(model.connectInFlight(for: board.id),
                       "and no other card may claim the attempt")
        XCTAssertFalse(model.manualConnectInFlight,
                       "a card's connect must not also spin the address row")

        await connecting.value

        XCTAssertNil(model.connectingBoardID)
        XCTAssertFalse(model.isConnecting)
        XCTAssertFalse(model.connectInFlight(for: second.id))
    }

    /// A typed address has no card to spin, so the spinner belongs beside the
    /// field. Showing it on a discovered card as well would claim two
    /// attempts are running against two different boards.
    func testATypedAddressSpinsBesideTheFieldAndNotOnACard() async {
        let model = ConnectModel(app: makeApp())
        model.boards = [board]
        model.manualAddress = "192.168.1.99"

        let connecting = Task { await model.connectManually() }
        await Task.yield()

        XCTAssertTrue(model.manualConnectInFlight)
        XCTAssertFalse(model.connectInFlight(for: board.id),
                       "a discovered card must not spin for an address that was typed")

        await connecting.value

        XCTAssertFalse(model.manualConnectInFlight)
        XCTAssertNil(model.connectingBoardID)
    }

    // MARK: Board labels

    /// The address is the only thing on a card that tells a real board from
    /// something else on the network wearing its name, so it is always shown
    /// in full rather than only when two cards would otherwise match.
    func testBoardAddressAlwaysIncludesThePort() {
        XCTAssertEqual(BoardAddressLabel.text(for: board), "192.168.1.50:4420")
    }

    /// Two instances on one Pi differ only by port.
    func testBoardAddressTellsTwoInstancesOnOneHostApart() {
        let second = DiscoveredBoard(id: "http://192.168.1.50:4421",
                                     name: "Garage",
                                     host: URL(string: "http://192.168.1.50:4421")!)
        XCTAssertEqual(BoardAddressLabel.text(for: second), "192.168.1.50:4421")
        XCTAssertNotEqual(BoardAddressLabel.text(for: board), BoardAddressLabel.text(for: second))
    }

    /// An address with no port at all still reads as an address.
    func testBoardAddressFallsBackToTheHostAloneWithoutAPort() {
        let portless = DiscoveredBoard(id: "https://board.example.com",
                                       name: "Studio",
                                       host: URL(string: "https://board.example.com")!)
        XCTAssertEqual(BoardAddressLabel.text(for: portless), "board.example.com")
    }

    // MARK: Rendering

    func testConnectScreenRendersInEveryState() {
        let app = makeApp()
        let image = RenderHarness.image(ConnectScreen().environment(app).background(Fiesta.Colors.background).preferredColorScheme(.dark))
        let attachment = XCTAttachment(image: image)
        attachment.name = "Connect — looking for boards"
        attachment.lifetime = .keepAlways
        add(attachment)

        let withError = makeApp()
        withError.errorMessage = "This FiestaBoard has no account yet."
        RenderHarness.render(ConnectScreen().environment(withError))
    }

    func testSignInScreenRenders() {
        let image = RenderHarness.image(SignInScreen().environment(makeApp()).background(Fiesta.Colors.background).preferredColorScheme(.dark))
        let attachment = XCTAttachment(image: image)
        attachment.name = "Sign in — presentation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDiscoveredBoardCardRenders() {
        RenderHarness.render(DiscoveredBoardCard(board: board, address: "192.168.1.50:4420") {})
    }

    /// Rendering `ConnectScreen` with no model only ever reached the empty
    /// state, so the grid, the cards and the two spinner decisions in the
    /// body had never been executed by a render at all.
    func testConnectScreenRendersTheGridWithAConnectInFlight() async {
        let app = makeApp()
        let model = ConnectModel(app: app)
        // A browse already running, so the screen's own `.onAppear` scan is
        // rejected instead of reaching for real Bonjour under a unit test.
        let discovery = NeverEndingDiscovery()
        let scan = Task { await model.startScan(using: discovery,
                                                patience: Self.patienceThatOutlastsTheTest) }
        await settle(until: "the browse to start looking") { model.scanState == .looking }
        discovery.publish([board, second])
        await settle(until: "both boards to land") { model.boards.count == 2 }

        let connecting = Task { await model.connect(to: board.host, name: board.name) }
        await Task.yield()
        XCTAssertTrue(model.connectInFlight(for: board.id))

        let image = RenderHarness.image(ConnectScreen(model: model).environment(app).background(Fiesta.Colors.background).preferredColorScheme(.dark))
        let attachment = XCTAttachment(image: image)
        attachment.name = "Connect — discovered boards"
        attachment.lifetime = .keepAlways
        add(attachment)
        await connecting.value

        model.stopScan()
        await scan.value
    }

    /// The spinner lives inside the button's label so it lifts with the card;
    /// rendering it is the cheapest guard against it being moved back out.
    func testDiscoveredBoardCardRendersWhileConnecting() {
        RenderHarness.render(DiscoveredBoardCard(board: board,
                                                 address: "192.168.1.50:4420",
                                                 isConnecting: true) {})
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
