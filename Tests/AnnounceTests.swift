import XCTest
@testable import FiestaBoardTV

/// What the screens actually say out loud.
///
/// Announcements are the only feedback several of these screens give — the
/// text they set is non-focusable, so with focus down on a field or a button
/// a failure that is not spoken is a screen that quietly did nothing. Before
/// `Announce.sink` existed nothing here could be asserted at all: every
/// `Announce.say` in the app could have been deleted and the suite stayed
/// green.
@MainActor
final class AnnounceTests: XCTestCase {

    private struct Heard: Equatable {
        let kind: Announce.Kind
        let message: String?
    }

    private var heard: [Heard] = []
    private var realSink: Announce.Sink!

    /// Only what VoiceOver was asked to speak, in order.
    private var spoken: [String] {
        heard.filter { $0.kind == .announcement }.compactMap { $0.message }
    }

    /// One sink per process, so this test owns putting the real one back.
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        heard = []
        realSink = Announce.sink
        Announce.sink = { [weak self] kind, message in
            self?.heard.append(Heard(kind: kind, message: message))
        }
    }

    override func tearDown() {
        Announce.sink = realSink
        StubURLProtocol.reset()
        super.tearDown()
    }

    private let host = URL(string: "http://192.168.1.50:4420")!

    private func makeApp() -> AppModel {
        AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.announce.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
    }

    /// An app parked on sign-in for a board that wants credentials.
    private func makeSignedOutApp() async -> AppModel {
        let app = makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        _ = try? await app.connection.connect(to: host, displayName: "Board")
        app.route = .signIn
        return app
    }

    /// The one that matters most. A refused password used to say nothing at
    /// all, so the next press went straight into the board's
    /// ten-failures-a-minute lockout — and then the *correct* password was
    /// refused too.
    func testARefusedPasswordIsSpoken() async throws {
        let app = await makeSignedOutApp()
        StubURLProtocol.enqueue(.json(#"{"detail":"Invalid username or password"}"#, status: 401),
                                for: "/api/auth/login")
        let model = SignInModel(app: app)
        model.username = "jeffre"
        model.password = "wrong"
        await model.submit()

        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertEqual(spoken.last, message,
                       "the failure on screen must also be the last thing said")
        XCTAssertTrue(spoken.contains("Signing in…"),
                      "the press itself is acknowledged before the wait")
    }

    /// Why `Announce.say(_:recordingIn:)` exists rather than an `.onChange`
    /// in the view: pressing Sign in twice on an empty form sets the same
    /// string twice, which is no transition at all. An observer of
    /// `errorMessage` would speak once and then stay silent on every
    /// subsequent press.
    func testTwoIdenticalFailuresAreBothSpoken() async throws {
        let model = SignInModel(app: await makeSignedOutApp())

        await model.submit()
        let first = try XCTUnwrap(model.errorMessage)
        await model.submit()

        XCTAssertEqual(model.errorMessage, first,
                       "the property never changed — only the announcements did")
        XCTAssertEqual(spoken, [first, first])
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url.path.contains("/auth/login") },
                       "an empty form never reaches the board — the two presses are pure UI")
    }

    /// Connect is the first screen anyone sees, and a board that does not
    /// answer leaves nothing focusable to read.
    func testAConnectFailureIsSpoken() async throws {
        let model = ConnectModel(app: makeApp())
        // Nothing enqueued: the request fails at the transport.
        await model.connect(to: host, name: "FiestaBoard")

        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertEqual(spoken.last, message)
        XCTAssertTrue(message.contains("192.168.1.50"))
    }

    /// The same helper carries the other screens. A panel list that failed to
    /// load is a screen with no panels on it and no spoken reason why.
    func testAFailedPanelLoadIsSpoken() async throws {
        let app = makeApp()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try? await app.connection.connect(to: host, displayName: "Board")

        let model = PanelsModel(app: app)
        await model.load()   // nothing enqueued for /api/panels

        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertEqual(spoken.last, message)
    }
}
