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
        do { try await store.signIn(username: "user", password: "secret"); XCTFail("storage failure expected") }
        catch DeviceCredentialError.storageFailed {}
        XCTAssertTrue(store.isSignedOut)
        XCTAssertEqual(failing.value?.password, "old-secret")
        XCTAssertNil(store.client?.deviceToken)
    }
    func testStoredPasswordMigratesOnceWhenCapabilityEnabled() async throws {
        try credentials.save(StoredCredential(username: "user", password: "secret"), for: host.absoluteString)
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled), for: "/auth/status")
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.token), for: "/auth/device/login")
        authenticated()
        let result = try await store.connect(to: host, displayName: "Board")
        XCTAssertEqual(result, .ready)
        XCTAssertNil(credentials.load(for: host.absoluteString)?.password)
        XCTAssertEqual(credentials.load(for: host.absoluteString)?.accessToken, "fb_tv_test-only")
    }
}

private final class FailingCredentialStore: CredentialStore {
    var value: StoredCredential?
    func save(_ credential: StoredCredential, for account: String) throws { throw KeychainError.unexpectedStatus(-1) }
    func load(for account: String) -> StoredCredential? { value }
    func delete(for account: String) throws { value = nil }
    func deleteAll() throws { value = nil }
}
