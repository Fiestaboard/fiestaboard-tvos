import XCTest
@testable import FiestaBoardTV

/// A9 — legacy password sign-ins migrate to a revocable TV credential,
/// quietly. A failed migration leaves the TV signed in on its password and
/// retries later; a modern sign-in is left alone; nothing is left behind.
@MainActor
final class LegacyMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var credentials: InMemoryCredentialStore!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let host = URL(string: "http://board.test:4420")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        defaults = UserDefaults(suiteName: UUID().uuidString)!
        credentials = InMemoryCredentialStore()
    }

    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func makeStore() -> ConnectionStore {
        ConnectionStore(defaults: defaults, credentials: credentials,
                        clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) },
                        clock: { [unowned self] in self.now })
    }

    private var signedOutStatus: String { DeviceAuthorizationTests.enabled }
    private var signedInStatus: String {
        DeviceAuthorizationTests.enabled.replacingOccurrences(of: "\"authenticated\":false", with: "\"authenticated\":true")
    }

    private func saveLegacy() throws {
        try credentials.save(.legacyPassword(username: "user", password: "secret"), for: host.absoluteString)
    }

    private func count(_ path: String) -> Int { StubURLProtocol.requests.filter { $0.url.path == path }.count }
    private var exchanges: Int { count("/api/auth/device/login") }
    private var legacyLogins: Int { count("/api/auth/login") }

    /// Connect with a stored password while the hub offers TV sign-in.
    private func connect(exchange: StubURLProtocol.Stub?, legacyLogin: Bool) async throws -> (ConnectionStore, ConnectResult) {
        let store = makeStore()
        StubURLProtocol.enqueue(.json(signedOutStatus), for: "/api/auth/status")
        if let exchange { StubURLProtocol.enqueue(exchange, for: "/auth/device/login") }
        if exchange.map({ $0.status == 200 }) == true {
            StubURLProtocol.enqueue(.json(signedInStatus), for: "/api/auth/status")
        }
        if legacyLogin { StubURLProtocol.enqueue(.json("{}"), for: "/api/auth/login") }
        let result = try await store.connect(to: host, displayName: "Board")
        return (store, result)
    }

    // MARK: legacy → migrated

    func testALegacyPasswordMigratesAndLeavesNoPasswordBehind() async throws {
        try saveLegacy()
        let (store, result) = try await connect(exchange: .json(DeviceAuthorizationTests.token), legacyLogin: false)
        XCTAssertEqual(result, .ready)
        XCTAssertFalse(store.isSignedOut)
        XCTAssertTrue(store.usesDeviceCredential)
        XCTAssertEqual(credentials.load(for: host.absoluteString)?.accessToken, "fb_tv_test-only")
        XCTAssertNil(credentials.load(for: host.absoluteString)?.password, "the password is replaced, not kept")
        XCTAssertNil(credentials.load(for: host.absoluteString + ".pending-device"), "no staging item left")
        XCTAssertNil(defaults.object(forKey: "fiestaboard.deviceMigrationRetryAt." + host.absoluteString))
        XCTAssertEqual(legacyLogins, 0)
    }

    // MARK: migration failure → still signed in, retry later

    func testAFailedMigrationStaysSignedInOnThePasswordAndRetriesLater() async throws {
        for (name, failure) in [("booting hub", StubURLProtocol.Stub.json("{}", status: 503)),
                                ("session limit", .json(#"{"error":"session_limit"}"#, status: 409)),
                                ("rate limited", .json(#"{"error":"rate_limited"}"#, status: 429)),
                                ("bad response", .json("{}"))] {
            StubURLProtocol.reset()
            try credentials.deleteAll()
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("fiestaboard.") {
                defaults.removeObject(forKey: key)
            }
            try saveLegacy()
            let (store, result) = try await connect(exchange: failure, legacyLogin: true)
            XCTAssertEqual(result, .ready, name)
            XCTAssertFalse(store.isSignedOut, "\(name): still signed in")
            XCTAssertFalse(store.usesDeviceCredential, name)
            XCTAssertEqual(credentials.load(for: host.absoluteString)?.password, "secret", "\(name): password kept for now")
            XCTAssertNil(credentials.load(for: host.absoluteString + ".pending-device"), name)
            XCTAssertEqual(exchanges, 1, name)
            XCTAssertEqual(legacyLogins, 1, "\(name): the legacy session keeps the TV working")
        }
    }

    private var retryKey: String { "fiestaboard.deviceMigrationRetryAt." + host.absoluteString }

    /// #32 review M1: the exchange succeeds, validating the new token fails
    /// (503) and the legacy login fails too (503). The password is still
    /// good, so the TV must not be left signed out, now or after a relaunch.
    private func exchangeThenValidationFails(validation: StubURLProtocol.Stub,
                                             legacyLogin: StubURLProtocol.Stub) async throws -> (ConnectionStore, ConnectResult) {
        let store = makeStore()
        StubURLProtocol.enqueue(.json(signedOutStatus), for: "/api/auth/status")
        StubURLProtocol.enqueue(validation, for: "/api/auth/status")
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.token), for: "/auth/device/login")
        StubURLProtocol.enqueue(legacyLogin, for: "/api/auth/login")
        let result = try await store.connect(to: host, displayName: "Board")
        return (store, result)
    }

    func testAFailedValidationAndAFailedLegacyLoginLeaveTheTVSignedIn() async throws {
        try saveLegacy()
        let (store, _) = try await exchangeThenValidationFails(validation: .json("{}", status: 503),
                                                               legacyLogin: .json("{}", status: 503))
        XCTAssertFalse(store.isSignedOut, "a valid saved password is not a signed-out TV")
        XCTAssertFalse(store.usesDeviceCredential)
        XCTAssertEqual(credentials.load(for: host.absoluteString)?.password, "secret")
        XCTAssertNil(credentials.load(for: host.absoluteString + ".pending-device"))
        XCTAssertNotNil(defaults.object(forKey: retryKey), "retried later")

        // Relaunch: a fresh store over the same defaults and Keychain.
        let relaunched = makeStore()
        XCTAssertFalse(relaunched.isSignedOut, "still signed in after a relaunch")
        now = now.addingTimeInterval(3600)
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(.json(signedOutStatus), for: "/api/auth/status")
        StubURLProtocol.enqueue(.json("{}"), for: "/api/auth/login")
        let result = try await relaunched.connect(to: host, displayName: "Board")
        XCTAssertEqual(result, .ready, "the password signs in once the hub is back")
        XCTAssertFalse(relaunched.isSignedOut)
        XCTAssertEqual(exchanges, 0, "inside the six hours: no exchange")
    }

    func testAFailedValidationFallsBackToTheLegacyLogin() async throws {
        try saveLegacy()
        let (store, result) = try await exchangeThenValidationFails(validation: .json("{}", status: 503),
                                                                    legacyLogin: .json("{}"))
        XCTAssertEqual(result, .ready)
        XCTAssertFalse(store.isSignedOut)
        XCTAssertFalse(store.usesDeviceCredential)
        XCTAssertEqual(credentials.load(for: host.absoluteString)?.password, "secret")
        XCTAssertEqual(legacyLogins, 1)
        XCTAssertNotNil(defaults.object(forKey: retryKey))
        XCTAssertFalse(makeStore().isSignedOut, "and after a relaunch")
    }

    /// #32 review S1: only the exchange's own 401 means a wrong password. A
    /// hub that doesn't accept the new token (`authenticated: false`) is a
    /// failed migration: fall back to the password and retry in six hours.
    func testARefusedNewTokenIsAFailedMigrationNotAWrongPassword() async throws {
        try saveLegacy()
        let (store, result) = try await exchangeThenValidationFails(validation: .json(signedOutStatus),
                                                                    legacyLogin: .json("{}"))
        XCTAssertEqual(result, .ready)
        XCTAssertFalse(store.isSignedOut)
        XCTAssertEqual(credentials.load(for: host.absoluteString)?.password, "secret")
        XCTAssertEqual(legacyLogins, 1, "the password still works")
        XCTAssertEqual(defaults.object(forKey: retryKey) as? Date, now.addingTimeInterval(ConnectionStore.migrationRetryInterval))
    }

    /// A legacy login the hub refuses after a failed migration still signs
    /// the TV out: that password really is wrong.
    func testARefusedLegacyLoginAfterAFailedMigrationSignsOut() async throws {
        try saveLegacy()
        let (store, result) = try await exchangeThenValidationFails(validation: .json("{}", status: 503),
                                                                    legacyLogin: .json("{}", status: 401))
        XCTAssertEqual(result, .needsSignIn)
        XCTAssertTrue(store.isSignedOut)
    }

    func testTheRetryWaitsSixHoursThenMigrates() async throws {
        try saveLegacy()
        _ = try await connect(exchange: .json("{}", status: 503), legacyLogin: true)
        XCTAssertEqual(ConnectionStore.migrationRetryInterval, 6 * 3600)

        // Inside the interval: the password signs in, no exchange.
        now = now.addingTimeInterval(3600)
        StubURLProtocol.reset()
        let (store, result) = try await connect(exchange: nil, legacyLogin: true)
        XCTAssertEqual(result, .ready)
        XCTAssertFalse(store.isSignedOut)
        XCTAssertEqual(exchanges, 0, "retry later, not on every launch")

        // After it: migrates.
        now = now.addingTimeInterval(ConnectionStore.migrationRetryInterval)
        StubURLProtocol.reset()
        let (later, laterResult) = try await connect(exchange: .json(DeviceAuthorizationTests.token), legacyLogin: false)
        XCTAssertEqual(laterResult, .ready)
        XCTAssertTrue(later.usesDeviceCredential)
        XCTAssertNil(credentials.load(for: host.absoluteString)?.password)
    }

    /// The retry time is written before the request: a response lost in
    /// flight must not let the next launch fire another exchange at once.
    func testTheRetryTimeIsRecordedBeforeTheExchange() async throws {
        try saveLegacy()
        var seen: Date?
        var exchange = StubURLProtocol.Stub.json("{}", status: 503)
        let key = "fiestaboard.deviceMigrationRetryAt." + host.absoluteString
        let defaults = self.defaults!
        exchange.beforeReply = { reply in seen = defaults.object(forKey: key) as? Date; reply() }
        _ = try await connect(exchange: exchange, legacyLogin: true)
        XCTAssertEqual(seen, now.addingTimeInterval(ConnectionStore.migrationRetryInterval))
    }

    // MARK: already modern → no-op

    func testAModernSignInIsLeftAlone() async throws {
        try credentials.save(.deviceToken(accessToken: "fb_tv_modern", sessionID: "s", expiresAt: now.addingTimeInterval(1000)),
                             for: host.absoluteString)
        let store = makeStore()
        StubURLProtocol.enqueue(.json(signedInStatus), for: "/api/auth/status")
        let result = try await store.connect(to: host, displayName: "Board")
        XCTAssertEqual(result, .ready)
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        _ = try await store.authorized { try await $0.panels() }
        XCTAssertEqual(exchanges, 0)
        XCTAssertEqual(legacyLogins, 0)
        XCTAssertEqual(credentials.load(for: host.absoluteString)?.accessToken, "fb_tv_modern")
    }

    // MARK: a changed password still needs signing in

    func testARejectedPasswordNeedsSignIn() async throws {
        try saveLegacy()
        let store = makeStore()
        StubURLProtocol.enqueue(.json(signedOutStatus), for: "/api/auth/status")
        StubURLProtocol.enqueue(.json(#"{"error":"invalid_credentials"}"#, status: 401), for: "/auth/device/login")
        let result = try await store.connect(to: host, displayName: "Board")
        XCTAssertEqual(result, .needsSignIn)
        XCTAssertEqual(legacyLogins, 0, "a password the hub refused is not offered again")
    }

    // MARK: installs stranded by the old once-only flag

    func testAnInstallStrandedByTheOldFlagMigrates() async throws {
        try saveLegacy()
        defaults.set(true, forKey: "fiestaboard.deviceMigration." + host.absoluteString)
        let (store, result) = try await connect(exchange: .json(DeviceAuthorizationTests.token), legacyLogin: false)
        XCTAssertEqual(result, .ready)
        XCTAssertTrue(store.usesDeviceCredential)
        XCTAssertNil(defaults.object(forKey: "fiestaboard.deviceMigration." + host.absoluteString))
    }

    // MARK: never logged

    func testNoCredentialIsLogged() throws {
        for file in ["Sources/Core/ConnectionStore.swift", "Sources/Core/Credentials.swift",
                     "Sources/Core/DeviceAuthorization.swift"] {
            let source = try String(contentsOf: TVSnapshot.repoRoot.appendingPathComponent(file), encoding: .utf8)
            for call in ["print(", "NSLog(", "Logger(", "os_log(", ".debug(", ".info(", ".error("] {
                XCTAssertFalse(source.contains(call), "\(file) must not log (\(call))")
            }
        }
    }
}

/// A9 — FiestaBot is retired on TV.
final class FiestaBotRetirementTests: XCTestCase {
    func testNoFiestaBotSourcesRemain() throws {
        let fm = FileManager.default
        for dir in ["Sources/UI", "Sources/Core"] {
            let names = try fm.contentsOfDirectory(atPath: TVSnapshot.repoRoot.appendingPathComponent(dir).path)
            XCTAssertTrue(names.filter { $0.hasPrefix("FiestaBot") || $0.hasPrefix("FiestaChat") || $0.contains("+Chat") }.isEmpty,
                          "\(dir): \(names)")
        }
    }

    /// S5: the local-network purpose string no longer mentions FiestaBot or
    /// an AI provider.
    func testThePrivacyStringDropsTheFiestaBotClause() throws {
        let project = try String(contentsOf: TVSnapshot.repoRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        let line = try XCTUnwrap(project.split(separator: "\n").first { $0.contains("NSLocalNetworkUsageDescription") })
        XCTAssertFalse(line.contains("FiestaBot"), String(line))
        XCTAssertFalse(line.contains("AI provider"), String(line))
        XCTAssertTrue(line.contains("hub"), String(line))
    }
}
