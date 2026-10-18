import XCTest
@testable import FiestaBoardTV

@MainActor
final class ConnectionStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var credentials: InMemoryCredentialStore!
    private var store: ConnectionStore!
    private let host = URL(string: "http://192.168.1.50:4420")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        defaults = UserDefaults(suiteName: "tv.connection.\(UUID().uuidString)")!
        credentials = InMemoryCredentialStore()
        store = ConnectionStore(defaults: defaults,
                                credentials: credentials,
                                clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testConnectingToAnOpenInstanceIsImmediatelyReady() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        let result = try await store.connect(to: host, displayName: "FiestaBoard")
        XCTAssertEqual(result, .ready)
        XCTAssertEqual(store.saved?.host, host)
        XCTAssertEqual(store.client?.baseURL, host)
    }

    func testConnectingToALockedInstanceAsksForSignIn() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        let result = try await store.connect(to: host, displayName: "FiestaBoard")
        XCTAssertEqual(result, .needsSignIn)
    }

    /// An instance with auth on and no account yet cannot be signed into from
    /// a TV — the first user must be created in the web app.
    func testInstanceAwaitingSetupIsCalledOut() async throws {
        let json = """
        {"enabled":true,"setup_required":true,"authenticated":false,
         "username":null,"mode":"undecided","first_run":true}
        """
        StubURLProtocol.enqueue(.json(json), for: "/api/auth/status")
        let result = try await store.connect(to: host, displayName: "FiestaBoard")
        XCTAssertEqual(result, .needsSetup)
        // Nothing may have been mutated on the way to that answer. A board
        // that cannot be signed into must not become the saved connection,
        // because the next cold launch would restore it, skip Connect and
        // strand the app on a Panels grid that answers 409 to everything.
        XCTAssertNil(store.saved)
        XCTAssertNil(store.client)
    }

    /// The other half of the same bug, at the only point where it actually
    /// bit: the relaunch.
    func testABoardAwaitingSetupIsNotRestoredOnTheNextLaunch() async throws {
        let json = """
        {"enabled":true,"setup_required":true,"authenticated":false,
         "username":null,"mode":"undecided","first_run":true}
        """
        StubURLProtocol.enqueue(.json(json), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")

        let relaunched = ConnectionStore(defaults: defaults, credentials: credentials,
                                         clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        XCTAssertNil(relaunched.saved)
        let app = AppModel(connection: relaunched)
        app.start()
        XCTAssertEqual(app.route, .connect, "there must still be a way back to Connect")
    }

    /// And it must not take a working board down with it: choosing a second,
    /// unprovisioned board leaves the one that works alone.
    func testAnUnprovisionedBoardDoesNotDisplaceTheWorkingOne() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "Kitchen Board")

        let fresh = URL(string: "http://192.168.1.77:4420")!
        StubURLProtocol.enqueue(.json("""
        {"enabled":true,"setup_required":true,"authenticated":false,
         "username":null,"mode":"undecided","first_run":true}
        """), for: "/api/auth/status")
        let result = try await store.connect(to: fresh, displayName: "New Board")

        XCTAssertEqual(result, .needsSetup)
        XCTAssertEqual(store.saved?.host, host)
        XCTAssertEqual(store.saved?.displayName, "Kitchen Board")
    }

    func testAnAlreadyAuthenticatedSessionIsReady() async throws {
        let json = """
        {"enabled":true,"setup_required":false,"authenticated":true,
         "username":"jeffre","mode":"enabled","first_run":false}
        """
        StubURLProtocol.enqueue(.json(json), for: "/api/auth/status")
        let result = try await store.connect(to: host, displayName: "FiestaBoard")
        XCTAssertEqual(result, .ready)
    }

    func testSignInStoresTheCredential() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")

        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")
        try await store.signIn(username: "jeffre", password: "hunter2")

        let saved = credentials.load(for: host.absoluteString)
        XCTAssertEqual(saved?.username, "jeffre")
        XCTAssertEqual(saved?.password, "hunter2")
    }

    func testFailedSignInStoresNothing() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")

        StubURLProtocol.enqueue(.json(#"{"detail":"bad"}"#, status: 401), for: "/api/auth/login")
        do {
            try await store.signIn(username: "jeffre", password: "wrong")
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {}

        XCTAssertNil(credentials.load(for: host.absoluteString))
    }

    /// The core recovery behaviour: an expired cookie re-logs in silently.
    func testA401TriggersOneSilentReLoginAndRetriesTheOperation() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "jeffre", password: "hunter2"),
                             for: host.absoluteString)

        StubURLProtocol.enqueue(.json(#"{"detail":"Not authenticated"}"#, status: 401), for: "/api/panels")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")

        let panels = try await store.authorized { try await $0.panels() }
        XCTAssertEqual(panels.count, 1)

        let paths = StubURLProtocol.requests.map(\.url.path)
        XCTAssertEqual(paths, ["/api/auth/status", "/api/panels", "/api/auth/login", "/api/panels"])
    }

    /// One attempt, not a loop: a changed password must surface, not spin.
    func testASecond401AfterReLoginSurfaces() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "jeffre", password: "stale"),
                             for: host.absoluteString)

        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/api/panels")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")
        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/api/panels")

        do {
            _ = try await store.authorized { try await $0.panels() }
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {}

        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url.path == "/api/auth/login" }.count, 1,
                       "exactly one re-login attempt")
    }

    /// The board locks an IP out after ten failed logins in a minute, so a
    /// credential it has already rejected must not be spent again by the
    /// next screen that loads. Otherwise a stale password becomes a lockout,
    /// and the lockout then refuses the correct password too.
    func testARejectedCredentialIsNotSpentAgainOnTheNextCall() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "jeffre", password: "stale"),
                             for: host.absoluteString)

        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/api/panels")
        StubURLProtocol.enqueue(.json(#"{"detail":"Invalid username or password"}"#, status: 401),
                                for: "/api/auth/login")
        do {
            _ = try await store.authorized { try await $0.panels() }
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {}

        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/api/panels")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")
        do {
            _ = try await store.authorized { try await $0.panels() }
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {}

        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url.path == "/api/auth/login" }.count, 1,
                       "a rejected credential must not be retried until someone signs in")
    }

    /// Signing in by hand is the event that makes the silent path trustworthy
    /// again — otherwise the cooldown would outlast the fix.
    func testSigningInClearsTheRejectedCredentialBlock() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "jeffre", password: "stale"),
                             for: host.absoluteString)

        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/api/panels")
        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/api/auth/login")
        _ = try? await store.authorized { try await $0.panels() }

        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")
        try await store.signIn(username: "jeffre", password: "correct")

        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/api/panels")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        let panels = try await store.authorized { try await $0.panels() }
        XCTAssertEqual(panels.count, 1, "the silent re-login should work again after signing in")
    }

    func testA401WithNoStoredCredentialSurfacesImmediately() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")

        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/api/panels")
        do {
            _ = try await store.authorized { try await $0.panels() }
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {}

        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url.path == "/api/auth/login" })
    }

    func testTheConnectionAndDefaultPanelSurviveARestart() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "Kitchen Board")
        store.setDefaultPanel(ref: "abc123def456")

        let reloaded = ConnectionStore(defaults: defaults,
                                       credentials: credentials,
                                       clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        XCTAssertEqual(reloaded.saved?.host, host)
        XCTAssertEqual(reloaded.saved?.displayName, "Kitchen Board")
        XCTAssertEqual(reloaded.saved?.defaultPanelRef, "abc123def456")
        XCTAssertEqual(reloaded.client?.baseURL, host,
                       "a restored connection must have a client pointed at the saved board")
    }

    /// `SavedConnection`'s decoder is hand-written so a blob on disk can be
    /// missing anything but the host: the synthesized one hard-decodes every
    /// non-optional property, so the first release that added a field would
    /// have thrown on the blob every shipped TV already had and woken them
    /// all up unpaired. Every other test here writes the blob through the
    /// current encoder, which always supplies every field — so nothing had
    /// ever handed that decoder an older shape.
    func testAConnectionBlobMissingEverythingButTheHostStillRestores() {
        defaults.set(Data(#"{"host":"http://192.168.1.50:4420"}"#.utf8),
                     forKey: "fiestaboard.connection")

        let restored = ConnectionStore(
            defaults: defaults, credentials: credentials,
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })

        XCTAssertEqual(restored.saved?.host, host)
        XCTAssertEqual(restored.saved?.displayName, "192.168.1.50",
                       "a blob with no name falls back to the address, not to nothing")
        XCTAssertNil(restored.saved?.defaultPanelRef)
        XCTAssertEqual(restored.client?.baseURL, host)
    }

    func testSignOutClearsTheCredentialButKeepsTheHost() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "a", password: "1"), for: host.absoluteString)

        store.signOut()
        XCTAssertNil(credentials.load(for: host.absoluteString))
        XCTAssertEqual(store.saved?.host, host)
    }

    func testSignOutClearsTheSessionAndPersistsTheSignInRoute() async throws {
        let cookieHost = URL(string: "http://board.example:4420")!
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        _ = try await store.connect(to: cookieHost, displayName: "FiestaBoard")
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "board.example", .path: "/", .name: "fiestaboard_session",
            .value: "session-token"
        ]))
        HTTPCookieStorage.shared.setCookie(cookie)
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }
        XCTAssertTrue(HTTPCookieStorage.shared.cookies(for: cookieHost)?.contains { $0.name == cookie.name } ?? false,
                      "the test must begin with an authenticated cookie")

        store.signOut()
        XCTAssertFalse(HTTPCookieStorage.shared.cookies(for: cookieHost)?.contains { $0.name == cookie.name } ?? false)

        let restored = ConnectionStore(defaults: defaults, credentials: credentials,
                                       clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        let app = AppModel(connection: restored)
        app.start()
        XCTAssertEqual(app.route, .signIn)
    }

    func testReconnectingToAnOpenBoardClearsTheSignedOutRoute() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        store.signOut()
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")

        let app = AppModel(connection: store)
        app.start()
        XCTAssertEqual(app.route, .panels)
    }

    // MARK: The silent login inside connect()

    /// Connecting to a board we already hold a password for must not ask for
    /// it again — this branch existed from the start and no test entered it.
    func testConnectSpendsAStoredCredentialRatherThanAskingForAPassword() async throws {
        try credentials.save(StoredCredential(username: "jeffre", password: "hunter2"),
                             for: host.absoluteString)
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")

        let result = try await store.connect(to: host, displayName: "FiestaBoard")
        XCTAssertEqual(result, .ready)
        XCTAssertEqual(StubURLProtocol.requests.map(\.url.path),
                       ["/api/auth/status", "/api/auth/login"])
    }

    /// A stored password the board no longer accepts falls through to the
    /// sign-in screen rather than reporting success.
    func testConnectFallsBackToSignInWhenTheStoredCredentialIsRefused() async throws {
        try credentials.save(StoredCredential(username: "jeffre", password: "stale"),
                             for: host.absoluteString)
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        StubURLProtocol.enqueue(.json(#"{"detail":"Invalid username or password"}"#, status: 401),
                                for: "/api/auth/login")

        let result = try await store.connect(to: host, displayName: "FiestaBoard")
        XCTAssertEqual(result, .needsSignIn)
    }

    /// The silent branch used to return `.ready` while leaving `signedOut`
    /// set, so the next cold boot asked for a password it had just used.
    func testTheSilentLoginClearsTheSignedOutRoute() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")
        try await store.signIn(username: "jeffre", password: "hunter2")
        store.signOut()
        XCTAssertTrue(store.isSignedOut, "the test must begin signed out")

        try credentials.save(StoredCredential(username: "jeffre", password: "hunter2"),
                             for: host.absoluteString)
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/api/auth/status")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")
        let reconnected = try await store.connect(to: host, displayName: "FiestaBoard")
        XCTAssertEqual(reconnected, .ready)

        XCTAssertFalse(store.isSignedOut)
        let app = AppModel(connection: store)
        app.start()
        XCTAssertEqual(app.route, .panels)
    }

    // MARK: The cooldown's far edge

    /// Inside the window the credential stays in its box — the behaviour the
    /// lockout depends on, here pinned against a clock rather than against
    /// how fast the test happens to run.
    func testARejectedCredentialIsStillBlockedInsideTheCooldownWindow() async throws {
        let clock = TestClock()
        let store = makeStore(clock: clock)
        try await burnTheStoredCredential(on: store)

        clock.now += ConnectionStore.rejectedCredentialCooldown - 1
        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/api/panels")
        do {
            _ = try await store.authorized { try await $0.panels() }
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {}

        XCTAssertEqual(loginCount, 1, "still inside the cooldown, so no second attempt")
    }

    /// And the fall-through at the other end: once the window has passed the
    /// credential is offered again, so a board that was merely rebooting
    /// recovers on its own. Nothing ever entered this branch.
    func testTheCooldownExpiresAndTheSilentLoginIsTriedAgain() async throws {
        let clock = TestClock()
        let store = makeStore(clock: clock)
        try await burnTheStoredCredential(on: store)

        clock.now += ConnectionStore.rejectedCredentialCooldown + 1
        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/api/panels")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/api/auth/login")
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")

        let panels = try await store.authorized { try await $0.panels() }
        XCTAssertEqual(panels.count, 1)
        XCTAssertEqual(loginCount, 2, "the cooldown has passed, so one fresh attempt")
    }

    // MARK: Forgetting

    func testForgetClearsEverything() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "a", password: "1"), for: host.absoluteString)

        store.forget()
        XCTAssertNil(store.saved)
        XCTAssertNil(store.client)
        XCTAssertNil(credentials.load(for: host.absoluteString))
    }

    /// One board under two spellings — see `CredentialStore.deleteAll` — gets
    /// a keychain item per spelling, and "Forget this board" used to leave one
    /// of them behind.
    func testForgetClearsCredentialsSavedUnderEverySpellingOfTheBoard() async throws {
        let bonjourSpelling = URL(string: "http://kitchen.local:4420")!
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: bonjourSpelling, displayName: "Kitchen Board")
        try credentials.save(StoredCredential(username: "a", password: "1"),
                             for: bonjourSpelling.absoluteString)
        try credentials.save(StoredCredential(username: "a", password: "1"),
                             for: host.absoluteString)

        store.forget()

        XCTAssertNil(credentials.load(for: bonjourSpelling.absoluteString))
        XCTAssertNil(credentials.load(for: host.absoluteString),
                     "the other spelling of the same board must go too")
    }

    // MARK: Helpers

    private func makeStore(clock: TestClock) -> ConnectionStore {
        ConnectionStore(defaults: defaults,
                        credentials: credentials,
                        clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) },
                        clock: { clock.now })
    }

    private var loginCount: Int {
        StubURLProtocol.requests.filter { $0.url.path == "/api/auth/login" }.count
    }

    /// Connect, store a password the board will refuse, and spend it once so
    /// the cooldown is running.
    private func burnTheStoredCredential(on store: ConnectionStore) async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "jeffre", password: "stale"),
                             for: host.absoluteString)

        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/api/panels")
        StubURLProtocol.enqueue(.json(#"{"detail":"Invalid username or password"}"#, status: 401),
                                for: "/api/auth/login")
        _ = try? await store.authorized { try await $0.panels() }
        XCTAssertEqual(loginCount, 1, "the credential must have been spent once")
    }
}

/// A clock the test winds by hand, so a sixty-second cooldown can expire
/// without the test taking a minute to run.
private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_700_000_000)
}
