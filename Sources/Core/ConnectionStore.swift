import Foundation

/// The FiestaBoard this TV is paired with.
public struct SavedConnection: Codable, Equatable, Sendable {
    public var host: URL
    public var displayName: String
    /// Panel to open straight into at launch, if the user chose one.
    public var defaultPanelRef: String?

    public init(host: URL, displayName: String, defaultPanelRef: String? = nil) {
        self.host = host
        self.displayName = displayName
        self.defaultPanelRef = defaultPanelRef
    }

    private enum CodingKeys: String, CodingKey {
        case host, displayName, defaultPanelRef
    }

    /// Hand-written rather than synthesized, because the synthesized decoder
    /// hard-decodes every non-optional property: adding one field in 1.1 would
    /// have thrown on the blob every shipped TV already has on disk, and every
    /// one of them would have woken up unpaired. Only `host` is load-bearing —
    /// without it there is nothing to talk to. Everything else decodes
    /// leniently, the same shape `Panel` uses in Models.swift.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decode(URL.self, forKey: .host)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
            ?? host.host()
            ?? "FiestaBoard"
        defaultPanelRef = try c.decodeIfPresent(String.self, forKey: .defaultPanelRef)
    }
}

public enum ConnectResult: Equatable, Sendable {
    case ready
    case needsSignIn
    /// Auth is on but no account exists — only the web app can create one.
    case needsSetup
}

/// Owns which board we are talking to and whether we are allowed to.
///
/// Deliberately not an ObservableObject: Core stays free of Combine so the
/// Android port maps onto a ViewModel without unpicking Apple types. The UI
/// layer wraps this in an observable of its own.
public final class ConnectionStore: @unchecked Sendable {

    private enum Keys {
        static let connection = "fiestaboard.connection"
        static let signedOut = "fiestaboard.signedOut"
    }

    /// How long a rejected credential is left alone for.
    ///
    /// Matched to FiestaBoard's own lockout window: it refuses an IP after
    /// ten failed logins in sixty seconds.
    static let rejectedCredentialCooldown: TimeInterval = 60

    private let defaults: UserDefaults
    private let credentials: CredentialStore
    private let clientFactory: (URL) -> FiestaClient
    private let clock: () -> Date

    /// Guards `storedSaved`, `storedClient` and `silentLoginBlockedUntil`.
    ///
    /// The viewer's polling task reads this store off the main actor while
    /// screens mutate it on the main actor, so `@unchecked Sendable` needed
    /// something behind it. A lock and not an actor: a dozen call sites read
    /// `saved`/`client` from synchronous SwiftUI bodies and non-async computed
    /// properties that cannot `await`, and an `NSLock` transcribes to a Kotlin
    /// `Mutex` for the Android port while an actor does not.
    ///
    /// The rule for anyone editing this file: **never hold `lock` across an
    /// `await`.** Take what you need into locals, unlock, then suspend.
    private let lock = NSLock()

    /// When the silent re-login may be trusted again, if it has just failed.
    private var silentLoginBlockedUntil: Date?
    private var generation = UUID()
    private var capability: TVSignInCapability?
    private var capabilityKnown = false
    private var recoveryTask: Task<Void, Error>?
    private var recoveryID = UUID()
    public var connectionGeneration: UUID { lock.withLock { generation } }
    public var deviceSignInEnabled: Bool { lock.withLock { capability?.isEnabled ?? false } }
    public var usesDeviceCredential: Bool { client?.deviceToken != nil }
    public static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1" }

    /// Persisted before a migration request: a lost response must never cause
    /// another automatic password exchange on the next launch.
    private func migrationKey(_ host: URL) -> String { "fiestaboard.deviceMigration." + host.absoluteString }
    private func credentialAllowed(_ host: URL) -> Bool {
        !defaults.bool(forKey: "fiestaboard.credentialBlocked." + host.absoluteString) &&
            (!defaults.bool(forKey: "fiestaboard.credentialsQuarantined") ||
             defaults.bool(forKey: "fiestaboard.credentialAllowed." + host.absoluteString))
    }
    private func loadCredential(for host: URL) -> StoredCredential? {
        credentialAllowed(host) ? credentials.load(for: host.absoluteString) : nil
    }
    private func allowCredential(for host: URL) {
        defaults.removeObject(forKey: "fiestaboard.credentialBlocked." + host.absoluteString)
        defaults.set(true, forKey: "fiestaboard.credentialAllowed." + host.absoluteString)
    }
    private func removeCredential(for host: URL) {
        do { try credentials.delete(for: host.absoluteString) }
        catch {
            // A failed Keychain deletion must never resurrect a sign-in.
            defaults.set(true, forKey: "fiestaboard.credentialBlocked." + host.absoluteString)
        }
        try? credentials.delete(for: host.absoluteString + ".pending-device")
    }

    public func invalidatePendingSignIn() {
        lock.withLock { generation = UUID(); recoveryTask?.cancel(); recoveryTask = nil }
    }

    public func refreshSignInCapability() async throws {
        let (client, generation) = lock.withLock { (storedClient, self.generation) }
        guard let client else { return }
        let status = try await client.authStatus()
        try lock.withLock {
            try checkCurrentLocked(generation)
            capability = status.tvSignIn; capabilityKnown = true
        }
    }

    private var storedSaved: SavedConnection?
    private var storedClient: FiestaClient?

    public var saved: SavedConnection? { lock.withLock { storedSaved } }
    public var client: FiestaClient? { lock.withLock { storedClient } }
    public var isSignedOut: Bool { defaults.bool(forKey: Keys.signedOut) }

    public init(defaults: UserDefaults = .standard,
                credentials: CredentialStore = KeychainCredentialStore(),
                clientFactory: @escaping (URL) -> FiestaClient = { FiestaClient(baseURL: $0) },
                clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.credentials = credentials
        self.clientFactory = clientFactory
        self.clock = clock

        if let data = defaults.data(forKey: Keys.connection),
           let connection = try? JSONDecoder().decode(SavedConnection.self, from: data) {
            self.storedSaved = connection
            // Restore the client too: a TV that reboots must come straight
            // back up on its panel without a round trip through Connect.
            try? credentials.delete(for: connection.host.absoluteString + ".pending-device")
            self.storedClient = clientFactory(connection.host)
            if !defaults.bool(forKey: Keys.signedOut),
               let credential = loadCredential(for: connection.host),
               case .deviceToken(let token, _, let expiry) = credential {
                if expiry > clock() { self.storedClient?.setDeviceToken(token) }
                else { defaults.set(true, forKey: Keys.signedOut); removeCredential(for: connection.host) }
            }
        }
    }

    // MARK: Connecting

    public func connect(to host: URL, displayName: String) async throws -> ConnectResult {
        let generation = lock.withLock { () -> UUID in
            self.generation = UUID()
            return self.generation
        }
        let host = FiestaClient.normalizedBaseURL(host)
        let client = clientFactory(host)
        if let credential = loadCredential(for: host),
           case .deviceToken(let token, _, let expiry) = credential, expiry > clock() {
            client.setDeviceToken(token)
        }
        let status: AuthStatus
        var rejectedDeviceToken = false
        do { status = try await client.authStatus() }
        catch FiestaError.unauthorized where client.deviceToken != nil {
            try checkCurrent(generation)
            client.setDeviceToken(nil)
            removeCredential(for: host)
            rejectedDeviceToken = true
            status = try await client.authStatus()
        }
        try checkCurrent(generation)

        // Before any mutation, and before anything reaches disk. A board with
        // auth on and no account yet cannot be used from a TV at all, and we
        // used to save it anyway: the next cold launch restored the connection,
        // routed straight past Connect to Panels, got 409 on every request and
        // sat on an empty grid with no way back. Recovery was deleting the app.
        // This is the first-run path for a brand-new FiestaBoard, so it is the
        // one order that matters most.
        if status.setupRequired { return .needsSetup }

        try lock.withLock {
            try checkCurrentLocked(generation)
            let carriedRef = storedSaved?.host == host ? storedSaved?.defaultPanelRef : nil
            let updated = SavedConnection(host: host,
                                          displayName: displayName,
                                          defaultPanelRef: carriedRef)
            // Client and saved connection move together — `authorized` keys
            // the stored credential off `saved.host` and would otherwise spend
            // one board's password against another board's client.
            storedClient = client
            storedSaved = updated
            silentLoginBlockedUntil = nil
            capability = status.tvSignIn; capabilityKnown = true
            writeToDisk(updated)
            defaults.set(status.enabled && !status.authenticated, forKey: Keys.signedOut)
        }

        if !status.enabled || status.authenticated {
            return .ready
        }

        // Auth is on and we are not authenticated. If we already hold a
        // credential for this host, spend it now rather than making someone
        // retype a password on a remote.
        if !rejectedDeviceToken, let stored = loadCredential(for: host) {
            do {
                try await recover(stored, client: client, host: host, generation: generation)
                // The same bookkeeping the by-hand sign-in does. This branch
                // used to return `.ready` with `signedOut` still true, so the
                // next cold boot went to Sign In and asked for a password it
                // had just used successfully.
                try lock.withLock {
                    try checkCurrentLocked(generation)
                    defaults.set(false, forKey: Keys.signedOut)
                    silentLoginBlockedUntil = nil
                }
                return .ready
            } catch {
                try checkCurrent(generation)
                return .needsSignIn
            }
        }
        return .needsSignIn
    }

    public func signIn(username: String, password: String) async throws {
        let (maybeClient, maybeSaved, generation) = lock.withLock { (storedClient, storedSaved, self.generation) }
        guard let client = maybeClient, let saved = maybeSaved else {
            throw FiestaError.transport("not connected")
        }
        if !lock.withLock({ capabilityKnown }) { try await refreshSignInCapability() }
        try lock.withLock { try checkCurrentLocked(generation); client.setDeviceToken(nil) }
        if deviceSignInEnabled {
            let result = try await client.loginDevice(username: username, password: password,
                                                     deviceName: "Apple TV", appVersion: Self.appVersion)
            try await adoptDeviceCredential(result, expectedGeneration: generation, issuingClient: client)
            return
        }
        try await client.login(username: username, password: password)
        try lock.withLock {
            try checkCurrentLocked(generation)
            do { try credentials.save(StoredCredential(username: username, password: password), for: saved.host.absoluteString) }
            catch { throw DeviceCredentialError.storageFailed }
            allowCredential(for: saved.host)
            defaults.set(false, forKey: Keys.signedOut)
            silentLoginBlockedUntil = nil
        }
    }

    public func adoptDeviceCredential(_ result: DeviceTokenResult, expectedGeneration: UUID,
                                      issuingClient: FiestaClient? = nil) async throws {
        // Capture the issuer independently of the current connection. A response
        // may arrive after a host switch, before staging has even started.
        let issuer = issuingClient ?? lock.withLock {
            generation == expectedGeneration ? storedClient : nil
        }
        var stagedHost: URL?
        var adoptingClient: FiestaClient?
        do {
            let credential = try result.credential(now: clock())
            let (client, host): (FiestaClient, URL) = try lock.withLock {
                try checkCurrentLocked(expectedGeneration)
                guard let client = storedClient, let saved = storedSaved,
                      client === issuer else { throw CancellationError() }
                stagedHost = saved.host
                adoptingClient = client
                // Stage in Keychain first. The old password is replaced only after
                // this token has also passed server validation.
                do { try credentials.save(credential, for: saved.host.absoluteString + ".pending-device") }
                catch { throw DeviceCredentialError.storageFailed }
                client.setDeviceToken(result.accessToken)
                defaults.set(true, forKey: Keys.signedOut)
                return (client, saved.host)
            }
            let status = try await client.authStatus()
            try lock.withLock {
                try checkCurrentLocked(expectedGeneration)
                guard status.authenticated else { throw FiestaError.unauthorized }
                do { try credentials.save(credential, for: host.absoluteString) }
                catch { throw DeviceCredentialError.storageFailed }
                allowCredential(for: host)
                defaults.set(false, forKey: Keys.signedOut)
                silentLoginBlockedUntil = nil
            }
        } catch {
            lock.withLock {
                if generation == expectedGeneration,
                   adoptingClient?.deviceToken == result.accessToken { adoptingClient?.setDeviceToken(nil) }
                if let host = stagedHost,
                   credentials.load(for: host.absoluteString + ".pending-device")?.accessToken == result.accessToken {
                    try? credentials.delete(for: host.absoluteString + ".pending-device")
                }
            }
            // Every failed adoption, including a staging failure or stale
            // generation, can leave an already-issued session on the server.
            // Use only the original issuer, never the replacement connection.
            if let issuer, result.accessToken.hasPrefix("fb_tv_"),
               !result.accessToken.contains(where: { $0.isWhitespace }) {
                let revoker = clientFactory(issuer.baseURL)
                revoker.setDeviceToken(result.accessToken)
                Task { try? await revoker.revokeDeviceSession() }
            }
            throw error
        }
        lock.withLock {
            if let host = stagedHost,
               credentials.load(for: host.absoluteString + ".pending-device")?.accessToken == result.accessToken {
                try? credentials.delete(for: host.absoluteString + ".pending-device")
            }
        }
    }

    private func recover(_ credential: StoredCredential, client: FiestaClient, host: URL, generation: UUID) async throws {
        switch credential {
        case .deviceToken:
            throw FiestaError.unauthorized
        case .legacyPassword(let username, let password):
            if !lock.withLock({ capabilityKnown }) { try await refreshSignInCapability() }
            if deviceSignInEnabled {
                try lock.withLock {
                    try checkCurrentLocked(generation)
                    guard !defaults.bool(forKey: migrationKey(host)) else { throw FiestaError.unauthorized }
                    defaults.set(true, forKey: migrationKey(host))
                    defaults.set(true, forKey: Keys.signedOut)
                }
                let result = try await client.loginDevice(username: username, password: password,
                                                         deviceName: "Apple TV", appVersion: Self.appVersion)
                try await adoptDeviceCredential(result, expectedGeneration: generation, issuingClient: client)
            } else {
                try await client.login(username: username, password: password)
            }
        }
    }

    // MARK: Authorized operations

    /// Run an authenticated request, recovering once from an expired session.
    ///
    /// Exactly one silent re-login per call: a stale cookie is routine and
    /// should be invisible, but a changed password must surface rather than
    /// spin.
    ///
    /// And once a credential has been rejected, it is not offered again for
    /// `rejectedCredentialCooldown`. Without that, every screen that loads
    /// spends another attempt on a password the board has already refused —
    /// and ten of those in a minute trip FiestaBoard's lockout, after which
    /// it refuses the *correct* password too. Signing in by hand lifts it.
    public func authorized<T>(_ operation: (FiestaClient) async throws -> T) async throws -> T {
        // One trip through the lock, up front. Everything below suspends, and
        // the client and host we are acting on must be the pair that was
        // current when the call started.
        let (maybeClient, maybeHost, generation) = try lock.withLock {
            guard !isSignedOut || recoveryTask != nil else { throw FiestaError.unauthorized }
            return (storedClient, storedSaved?.host, self.generation)
        }
        guard let client = maybeClient, let host = maybeHost else {
            throw FiestaError.transport("not connected")
        }
        // Serialize startup migration before public panel reads. A second
        // caller joins the same task even after capability negotiation finishes.
        let bootstrap = try lock.withLock { () -> (Task<Void, Error>, UUID)? in
            try checkCurrentLocked(generation)
            if let recoveryTask { return (recoveryTask, recoveryID) }
            guard !capabilityKnown, let stored = loadCredential(for: host), stored.password != nil else { return nil }
            recoveryID = UUID()
            let task = Task {
                try await self.refreshSignInCapability()
                if self.deviceSignInEnabled {
                    try await self.recover(stored, client: client, host: host, generation: generation)
                }
            }
            recoveryTask = task
            return (task, recoveryID)
        }
        if let (task, id) = bootstrap {
            defer { lock.withLock { if recoveryID == id { recoveryTask = nil } } }
            try await task.value
        }
        func perform() async throws -> T {
            try checkCurrent(generation)
            do {
                let result = try await operation(client)
                try checkCurrent(generation)
                return result
            } catch {
                try checkCurrent(generation)
                throw error
            }
        }
        do {
            return try await perform()
        } catch FiestaError.unauthorized {
            if client.deviceToken != nil {
                try lock.withLock {
                    try checkCurrentLocked(generation)
                    defaults.set(true, forKey: Keys.signedOut)
                    removeCredential(for: host)
                    self.generation = UUID()
                    recoveryTask?.cancel(); recoveryTask = nil
                    client.setDeviceToken(nil)
                }
                throw FiestaError.unauthorized
            }
            guard let stored = loadCredential(for: host),
                  !silentLoginIsBlocked else {
                throw FiestaError.unauthorized
            }
            do {
                let (task, id) = try lock.withLock { () -> (Task<Void, Error>, UUID) in
                    try checkCurrentLocked(generation)
                    if let existing = recoveryTask { return (existing, recoveryID) }
                    recoveryID = UUID()
                    let task = Task { try await self.recover(stored, client: client, host: host, generation: generation) }
                    recoveryTask = task
                    return (task, recoveryID)
                }
                defer { lock.withLock { if recoveryID == id { recoveryTask = nil } } }
                try await task.value
            } catch {
                try checkCurrent(generation)
                // An outage or cancellation says nothing about the password.
                // Blocking it would turn the next poll into a false sign-in prompt.
                if let failure = error as? FiestaError,
                   failure == .unauthorized || failure == .http(429) {
                    try lock.withLock {
                        try checkCurrentLocked(generation)
                        silentLoginBlockedUntil = clock().addingTimeInterval(Self.rejectedCredentialCooldown)
                    }
                }
                throw error
            }
            try lock.withLock {
                try checkCurrentLocked(generation)
                silentLoginBlockedUntil = nil
            }
            return try await perform()
        }
    }

    private var silentLoginIsBlocked: Bool {
        lock.withLock { () -> Bool in
            guard let until = silentLoginBlockedUntil else { return false }
            if clock() < until { return true }
            silentLoginBlockedUntil = nil
            return false
        }
    }

    // MARK: Preferences

    public func setDefaultPanel(ref: String?) {
        lock.withLock {
            guard var connection = storedSaved else { return }
            connection.defaultPanelRef = ref
            storedSaved = connection
            writeToDisk(connection)
        }
    }

    public func signOut() {
        let previousClient = client
        let hadToken = previousClient?.deviceToken != nil
        lock.withLock {
            generation = UUID()
            recoveryTask?.cancel(); recoveryTask = nil
            guard let saved = storedSaved else { return }
            // Per-host, unlike forget(): other boards retain their credentials.
            removeCredential(for: saved.host)
            clearCookies(for: saved.host)
            // Discard the private cookie jar, including any response that
            // arrives after this point. Keep a fresh client for manual sign-in.
            storedClient = clientFactory(saved.host)
            defaults.set(true, forKey: Keys.signedOut)
        }
        if hadToken { Task { try? await previousClient?.revokeDeviceSession() } }
    }

    public func forget() {
        let previousClient = client
        let hadToken = previousClient?.deviceToken != nil
        lock.withLock {
            generation = UUID()
            recoveryTask?.cancel(); recoveryTask = nil
            let previous = storedSaved
            storedSaved = nil
            storedClient = nil
            silentLoginBlockedUntil = nil
            if let previous { clearCookies(for: previous.host) }
            // A board may be remembered under both its Bonjour name and IP.
            // Forget must remove credentials under either spelling.
            do { try credentials.deleteAll() }
            catch {
                defaults.set(true, forKey: "fiestaboard.credentialsQuarantined")
                for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("fiestaboard.credentialAllowed.") {
                    defaults.removeObject(forKey: key)
                }
            }
            defaults.removeObject(forKey: Keys.connection)
            defaults.removeObject(forKey: Keys.signedOut)
        }
        if hadToken { Task { try? await previousClient?.revokeDeviceSession() } }
    }

    private func clearCookies(for host: URL) {
        for cookie in HTTPCookieStorage.shared.cookies(for: host) ?? [] {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private func writeToDisk(_ connection: SavedConnection) {
        if let data = try? JSONEncoder().encode(connection) {
            defaults.set(data, forKey: Keys.connection)
        }
    }

    private func checkCurrent(_ generation: UUID) throws {
        try lock.withLock { try checkCurrentLocked(generation) }
    }

    private func checkCurrentLocked(_ generation: UUID) throws {
        guard generation == self.generation, !Task.isCancelled else { throw CancellationError() }
    }
}
