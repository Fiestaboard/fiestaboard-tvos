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
            self.storedClient = clientFactory(connection.host)
        }
    }

    // MARK: Connecting

    public func connect(to host: URL, displayName: String) async throws -> ConnectResult {
        let client = clientFactory(host)
        let status = try await client.authStatus()

        // Before any mutation, and before anything reaches disk. A board with
        // auth on and no account yet cannot be used from a TV at all, and we
        // used to save it anyway: the next cold launch restored the connection,
        // routed straight past Connect to Panels, got 409 on every request and
        // sat on an empty grid with no way back. Recovery was deleting the app.
        // This is the first-run path for a brand-new FiestaBoard, so it is the
        // one order that matters most.
        if status.setupRequired { return .needsSetup }

        let connection = lock.withLock { () -> SavedConnection in
            let carriedRef = storedSaved?.host == host ? storedSaved?.defaultPanelRef : nil
            let updated = SavedConnection(host: host,
                                          displayName: displayName,
                                          defaultPanelRef: carriedRef)
            // Client and saved connection move together — `authorized` keys
            // the stored credential off `saved.host` and would otherwise spend
            // one board's password against another board's client.
            storedClient = client
            storedSaved = updated
            return updated
        }
        writeToDisk(connection)

        if !status.enabled || status.authenticated {
            defaults.set(false, forKey: Keys.signedOut)
            return .ready
        }

        // Auth is on and we are not authenticated. If we already hold a
        // credential for this host, spend it now rather than making someone
        // retype a password on a remote.
        if let stored = credentials.load(for: host.absoluteString) {
            do {
                try await client.login(username: stored.username, password: stored.password)
                // The same bookkeeping the by-hand sign-in does. This branch
                // used to return `.ready` with `signedOut` still true, so the
                // next cold boot went to Sign In and asked for a password it
                // had just used successfully.
                defaults.set(false, forKey: Keys.signedOut)
                lock.withLock { silentLoginBlockedUntil = nil }
                return .ready
            } catch {
                return .needsSignIn
            }
        }
        return .needsSignIn
    }

    public func signIn(username: String, password: String) async throws {
        let (maybeClient, maybeSaved) = lock.withLock { return (storedClient, storedSaved) }
        guard let client = maybeClient, let saved = maybeSaved else {
            throw FiestaError.transport("not connected")
        }
        try await client.login(username: username, password: password)
        defaults.set(false, forKey: Keys.signedOut)
        // A credential the board just accepted makes the silent path
        // trustworthy again.
        lock.withLock { silentLoginBlockedUntil = nil }
        // Only persist a credential the server just accepted.
        try? credentials.save(StoredCredential(username: username, password: password),
                              for: saved.host.absoluteString)
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
        let (maybeClient, maybeHost) = lock.withLock { return (storedClient, storedSaved?.host) }
        guard let client = maybeClient, let host = maybeHost else {
            throw FiestaError.transport("not connected")
        }
        do {
            return try await operation(client)
        } catch FiestaError.unauthorized {
            guard let stored = credentials.load(for: host.absoluteString),
                  !silentLoginIsBlocked else {
                throw FiestaError.unauthorized
            }
            do {
                try await client.login(username: stored.username, password: stored.password)
            } catch {
                lock.withLock {
                    silentLoginBlockedUntil = clock().addingTimeInterval(Self.rejectedCredentialCooldown)
                }
                throw error
            }
            lock.withLock { silentLoginBlockedUntil = nil }
            return try await operation(client)
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
        let updated = lock.withLock { () -> SavedConnection? in
            guard var connection = storedSaved else { return nil }
            connection.defaultPanelRef = ref
            storedSaved = connection
            return connection
        }
        guard let updated else { return }
        writeToDisk(updated)
    }

    public func signOut() {
        guard let saved else { return }
        // Per-host, unlike `forget()`: signing out of this board is not a
        // reason to drop a credential for a different one.
        try? credentials.delete(for: saved.host.absoluteString)
        clearCookies(for: saved.host)
        defaults.set(true, forKey: Keys.signedOut)
    }

    public func forget() {
        let previous = lock.withLock { () -> SavedConnection? in
            let previous = storedSaved
            storedSaved = nil
            storedClient = nil
            silentLoginBlockedUntil = nil
            return previous
        }
        if let previous { clearCookies(for: previous.host) }
        // Every credential, not just this host's. The same board is routinely
        // remembered under two spellings — Bonjour gives
        // `http://kitchen.local:4420`, typing the address gives
        // `http://192.168.1.50:4420` — so deleting by host left the other
        // spelling's password sitting in the keychain after "Forget".
        try? credentials.deleteAll()
        defaults.removeObject(forKey: Keys.connection)
        defaults.removeObject(forKey: Keys.signedOut)
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
}
