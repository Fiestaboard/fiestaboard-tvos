import XCTest
@testable import FiestaBoardTV

@MainActor
final class DeviceCredentialTests: XCTestCase {
    private var defaults: UserDefaults!
    private var credentials: InMemoryCredentialStore!
    private var store: ConnectionStore!
    private let host = URL(string: "http://board.test:4420")!
    override func setUp() {
        StubURLProtocol.reset()
        defaults = UserDefaults(suiteName: UUID().uuidString)!
        credentials = InMemoryCredentialStore()
        store = makeStore(credentials)
    }
    private func makeStore(_ credentials: CredentialStore) -> ConnectionStore {
        ConnectionStore(defaults: defaults, credentials: credentials, clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
    }
    private func connect() async throws {
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "Board")
    }
    private func token() throws -> DeviceTokenResult {
        try JSONDecoder().decode(DeviceTokenResult.self, from: Data(DeviceAuthorizationTests.token.utf8))
    }
    private func authenticated() {
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled.replacingOccurrences(of: "\"authenticated\":false", with: "\"authenticated\":true")), for: "/api/auth/status")
    }
    func testDirectPasswordStoresOnlyTokenAndRestoresWithoutPasswordReplay() async throws {
        try await connect()
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.token), for: "/auth/device/login")
        authenticated()
        try await store.signIn(username: "user", password: "password")
        XCTAssertNil(credentials.load(for: host.absoluteString)?.password)
        XCTAssertEqual(credentials.load(for: host.absoluteString)?.accessToken, "fb_tv_test-only")
        XCTAssertFalse(store.isSignedOut)
        let restarted = makeStore(credentials)
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        _ = try await restarted.authorized { try await $0.panels() }
        XCTAssertEqual(StubURLProtocol.requests.last?.authorization, "Bearer fb_tv_test-only")
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url.path == "/api/auth/login" })
    }
    func testRevokedTokenNeverReplaysPasswordAndStopsConcurrentWork() async throws {
        try await connect()
        authenticated()
        try await store.adoptDeviceCredential(token(), expectedGeneration: store.connectionGeneration)
        StubURLProtocol.enqueue(.json("{}", status: 401), for: "/api/panels")
        do { _ = try await store.authorized { try await $0.panels() }; XCTFail("401 expected") }
        catch FiestaError.unauthorized {}
        XCTAssertTrue(store.isSignedOut)
        XCTAssertNil(credentials.load(for: host.absoluteString))
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url.path == "/api/auth/login" })
    }
    func testOldGenerationCannotStoreCredentialAfterSignOut() async throws {
        try await connect()
        let generation = store.connectionGeneration
        store.signOut()
        do { try await store.adoptDeviceCredential(token(), expectedGeneration: generation); XCTFail("cancel expected") }
        catch is CancellationError {}
        XCTAssertNil(credentials.load(for: host.absoluteString))
        XCTAssertTrue(store.isSignedOut)
    }
    func testPersistenceFailureDoesNotAnnounceSuccessOrDeleteLegacyPassword() async throws {
        let failing = FailingCredentialStore()
        store = makeStore(failing)
        try await connect()
        failing.value = StoredCredential(username: "old", password: "old-secret")
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.token), for: "/auth/device/login")
        let revoked = expectation(description: "issued token is revoked after staging fails")
        var revokeResponse = StubURLProtocol.Stub.json("{}")
        revokeResponse.beforeReply = { reply in reply(); revoked.fulfill() }
        StubURLProtocol.enqueue(revokeResponse, for: "/auth/device/session")
        do { try await store.signIn(username: "user", password: "secret"); XCTFail("storage failure expected") }
        catch DeviceCredentialError.storageFailed {}
        XCTAssertTrue(store.isSignedOut)
        XCTAssertEqual(failing.value?.password, "old-secret")
        XCTAssertNil(store.client?.deviceToken)
        await fulfillment(of: [revoked], timeout: 2)
        let deletion = StubURLProtocol.requests.first { $0.method == "DELETE" }
        XCTAssertEqual(deletion?.url.absoluteString, host.absoluteString + "/api/auth/device/session")
        XCTAssertEqual(deletion?.authorization, "Bearer fb_tv_test-only")
    }
    func testLateDevicePasswordReplyRevokesAtIssuingHostBeforeStaging() async throws {
        try await connect()
        let loginReached = expectation(description: "password exchange is held")
        var release: (() -> Void)?
        var loginResponse = StubURLProtocol.Stub.json(DeviceAuthorizationTests.token)
        loginResponse.beforeReply = { reply in release = reply; loginReached.fulfill() }
        StubURLProtocol.enqueue(loginResponse, for: "/auth/device/login")
        let login = Task { try await store.signIn(username: "user", password: "secret") }
        await fulfillment(of: [loginReached], timeout: 2)
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: URL(string: "http://replacement.test")!, displayName: "Replacement")
        let revoked = expectation(description: "late token is revoked at original issuer")
        var revokeResponse = StubURLProtocol.Stub.json("{}")
        revokeResponse.beforeReply = { reply in reply(); revoked.fulfill() }
        StubURLProtocol.enqueue(revokeResponse, for: "/auth/device/session")
        release?()
        do { try await login.value; XCTFail("stale generation must cancel adoption") }
        catch is CancellationError {}
        await fulfillment(of: [revoked], timeout: 2)
        let deletion = StubURLProtocol.requests.first { $0.method == "DELETE" }
        XCTAssertEqual(deletion?.url.absoluteString, host.absoluteString + "/api/auth/device/session")
        XCTAssertEqual(deletion?.authorization, "Bearer fb_tv_test-only")
        XCTAssertNil(credentials.load(for: host.absoluteString))
        XCTAssertNil(credentials.load(for: host.absoluteString + ".pending-device"))
        XCTAssertNil(credentials.load(for: "http://replacement.test"))
        XCTAssertNil(store.client?.deviceToken)
    }

    func testStoredPasswordMigratesOnceWhenCapabilityEnabled() async throws {
        try credentials.save(StoredCredential(username: "user", password: "secret"), for: host.absoluteString)
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled), for: "/api/auth/status")
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.token), for: "/auth/device/login")
        authenticated()
        let result = try await store.connect(to: host, displayName: "Board")
        XCTAssertEqual(result, .ready)
        XCTAssertNil(credentials.load(for: host.absoluteString)?.password)
        XCTAssertEqual(credentials.load(for: host.absoluteString)?.accessToken, "fb_tv_test-only")
    }
    func testReconnectingWithRevokedTokenOffersSignInWithoutPasswordLogin() async throws {
        try credentials.save(.deviceToken(accessToken: "fb_tv_revoked", sessionID: "old", expiresAt: Date().addingTimeInterval(1000)), for: host.absoluteString)
        StubURLProtocol.enqueue(.json("{}", status: 401), for: "/api/auth/status")
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled), for: "/api/auth/status")
        let result = try await store.connect(to: host, displayName: "Board")
        XCTAssertEqual(result, .needsSignIn)
        XCTAssertTrue(store.deviceSignInEnabled)
        XCTAssertNil(credentials.load(for: host.absoluteString))
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url.path.hasSuffix("/login") })
    }
    func testColdStartMigratesBeforePublicDefaultPanelCanBypassAuthentication() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "Board")
        try credentials.save(.legacyPassword(username: "user", password: "secret"), for: host.absoluteString)
        let restored = makeStore(credentials)
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled), for: "/api/auth/status")
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.token), for: "/auth/device/login")
        authenticated()
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        _ = try await restored.authorized { try await $0.panel(ref: "1") }
        XCTAssertEqual(StubURLProtocol.requests.last?.authorization, "Bearer fb_tv_test-only")
        XCTAssertNil(credentials.load(for: host.absoluteString)?.password)
    }

    func testReplacementIsValidatedBeforeDeletingLegacyPassword() async throws {
        try await connect()
        try credentials.save(.legacyPassword(username: "old", password: "old-secret"), for: host.absoluteString)
        StubURLProtocol.enqueue(.json("{}", status: 401), for: "/api/auth/status")
        do { try await store.adoptDeviceCredential(token(), expectedGeneration: store.connectionGeneration); XCTFail("validation must fail") }
        catch FiestaError.unauthorized {}
        XCTAssertEqual(credentials.load(for: host.absoluteString)?.password, "old-secret")
        XCTAssertTrue(store.isSignedOut)
        XCTAssertNil(store.client?.deviceToken)
    }
    func testLateValidationAfterHostSwitchCannotOverwriteNewConnection() async throws {
        try await connect()
        let reached = expectation(description: "validation is held")
        var release: (() -> Void)?
        var response = StubURLProtocol.Stub.json(DeviceAuthorizationTests.enabled.replacingOccurrences(of: "\"authenticated\":false", with: "\"authenticated\":true"))
        response.beforeReply = { reply in release = reply; reached.fulfill() }
        StubURLProtocol.enqueue(response, for: "/api/auth/status")
        let result = try token()
        let generation = store.connectionGeneration
        let adoption = Task { try await store.adoptDeviceCredential(result, expectedGeneration: generation) }
        await fulfillment(of: [reached], timeout: 3)
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: URL(string: "http://replacement.test")!, displayName: "Replacement")
        release?()
        do { try await adoption.value; XCTFail("old adoption must cancel") } catch is CancellationError {}
        XCTAssertEqual(store.saved?.displayName, "Replacement")
        XCTAssertNil(credentials.load(for: "http://replacement.test"))
        XCTAssertNil(credentials.load(for: host.absoluteString))
    }

    func testFailedKeychainDeletionCannotRestoreSignInAfterRestartOrReconnect() async throws {
        let stubborn = UndeletableCredentialStore()
        store = makeStore(stubborn)
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "Board")
        stubborn.value = .deviceToken(accessToken: "fb_tv_stubborn", sessionID: "old", expiresAt: Date().addingTimeInterval(1000))
        store.signOut()
        let restarted = makeStore(stubborn)
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled), for: "/api/auth/status")
        _ = try await restarted.connect(to: host, displayName: "Board")
        XCTAssertNil(StubURLProtocol.requests.last?.authorization)
        XCTAssertTrue(restarted.isSignedOut)
    }

    func testConcurrentColdStartSharesOneMigration() async throws {
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try await store.connect(to: host, displayName: "Board")
        try credentials.save(.legacyPassword(username: "user", password: "secret"), for: host.absoluteString)
        let restored = makeStore(credentials)
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled), for: "/api/auth/status")
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.token), for: "/auth/device/login")
        authenticated()
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        async let first = try? restored.authorized { try await $0.panel(ref: "1") }
        async let second = try? restored.authorized { try await $0.panel(ref: "1") }
        let results = await [first, second]
        XCTAssertTrue(results.allSatisfy { $0 != nil })
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url.path.hasSuffix("/device/login") }.count, 1)
    }

}

private final class FailingCredentialStore: CredentialStore {
    var value: StoredCredential?
    func save(_ credential: StoredCredential, for account: String) throws { throw KeychainError.unexpectedStatus(-1) }
    func load(for account: String) -> StoredCredential? { value }
    func delete(for account: String) throws { value = nil }
    func deleteAll() throws { value = nil }
}

private final class UndeletableCredentialStore: CredentialStore {
    var value: StoredCredential?
    func save(_ credential: StoredCredential, for account: String) throws { value = credential }
    func load(for account: String) -> StoredCredential? { value }
    func delete(for account: String) throws { throw KeychainError.unexpectedStatus(-1) }
    func deleteAll() throws { throw KeychainError.unexpectedStatus(-1) }
}
