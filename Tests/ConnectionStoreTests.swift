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
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        let result = try await store.connect(to: host, displayName: "FiestaBoard")
        XCTAssertEqual(result, .ready)
        XCTAssertEqual(store.saved?.host, host)
        XCTAssertNotNil(store.client)
    }

    func testConnectingToALockedInstanceAsksForSignIn() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
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
        StubURLProtocol.enqueue(.json(json), for: "/auth/status")
        let result = try await store.connect(to: host, displayName: "FiestaBoard")
        XCTAssertEqual(result, .needsSetup)
    }

    func testAnAlreadyAuthenticatedSessionIsReady() async throws {
        let json = """
        {"enabled":true,"setup_required":false,"authenticated":true,
         "username":"jeffre","mode":"enabled","first_run":false}
        """
        StubURLProtocol.enqueue(.json(json), for: "/auth/status")
        let result = try await store.connect(to: host, displayName: "FiestaBoard")
        XCTAssertEqual(result, .ready)
    }

    func testSignInStoresTheCredential() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")

        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/auth/login")
        try await store.signIn(username: "jeffre", password: "hunter2")

        let saved = credentials.load(for: host.absoluteString)
        XCTAssertEqual(saved?.username, "jeffre")
        XCTAssertEqual(saved?.password, "hunter2")
    }

    func testFailedSignInStoresNothing() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusEnabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")

        StubURLProtocol.enqueue(.json(#"{"detail":"bad"}"#, status: 401), for: "/auth/login")
        do {
            try await store.signIn(username: "jeffre", password: "wrong")
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {}

        XCTAssertNil(credentials.load(for: host.absoluteString))
    }

    /// The core recovery behaviour: an expired cookie re-logs in silently.
    func testA401TriggersOneSilentReLoginAndRetriesTheOperation() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "jeffre", password: "hunter2"),
                             for: host.absoluteString)

        StubURLProtocol.enqueue(.json(#"{"detail":"Not authenticated"}"#, status: 401), for: "/panels")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/auth/login")
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/panels")

        let panels = try await store.authorized { try await $0.panels() }
        XCTAssertEqual(panels.count, 1)

        let paths = StubURLProtocol.requests.map(\.url.path)
        XCTAssertEqual(paths, ["/auth/status", "/panels", "/auth/login", "/panels"])
    }

    /// One attempt, not a loop: a changed password must surface, not spin.
    func testASecond401AfterReLoginSurfaces() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "jeffre", password: "stale"),
                             for: host.absoluteString)

        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/panels")
        StubURLProtocol.enqueue(.json(Fixtures.loginOK), for: "/auth/login")
        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/panels")

        do {
            _ = try await store.authorized { try await $0.panels() }
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {}

        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url.path == "/auth/login" }.count, 1,
                       "exactly one re-login attempt")
    }

    func testA401WithNoStoredCredentialSurfacesImmediately() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")

        StubURLProtocol.enqueue(.json(#"{"detail":"no"}"#, status: 401), for: "/panels")
        do {
            _ = try await store.authorized { try await $0.panels() }
            XCTFail("expected unauthorized")
        } catch FiestaError.unauthorized {}

        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url.path == "/auth/login" })
    }

    func testTheConnectionAndDefaultPanelSurviveARestart() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "Kitchen Board")
        store.setDefaultPanel(ref: "abc123def456")

        let reloaded = ConnectionStore(defaults: defaults,
                                       credentials: credentials,
                                       clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        XCTAssertEqual(reloaded.saved?.host, host)
        XCTAssertEqual(reloaded.saved?.displayName, "Kitchen Board")
        XCTAssertEqual(reloaded.saved?.defaultPanelRef, "abc123def456")
        XCTAssertNotNil(reloaded.client, "a restored connection must have a usable client")
    }

    func testSignOutClearsTheCredentialButKeepsTheHost() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "a", password: "1"), for: host.absoluteString)

        store.signOut()
        XCTAssertNil(credentials.load(for: host.absoluteString))
        XCTAssertEqual(store.saved?.host, host)
    }

    func testForgetClearsEverything() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "FiestaBoard")
        try credentials.save(StoredCredential(username: "a", password: "1"), for: host.absoluteString)

        store.forget()
        XCTAssertNil(store.saved)
        XCTAssertNil(store.client)
        XCTAssertNil(credentials.load(for: host.absoluteString))
    }
}
