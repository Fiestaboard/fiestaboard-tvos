import Foundation

/// The FiestaBoard this TV is paired with.
public struct SavedConnection: Codable, Equatable, Sendable {
    public var host: URL
    public var displayName: String
    /// Panel to open straight into at launch, if the user chose one.
    public var defaultPanelRef: String?
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

    /// When the silent re-login may be trusted again, if it has just failed.
    private var silentLoginBlockedUntil: Date?

    public private(set) var saved: SavedConnection?
    public private(set) var client: FiestaClient?
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
            self.saved = connection
            // Restore the client too: a TV that reboots must come straight
            // back up on its panel without a round trip through Connect.
            self.client = clientFactory(connection.host)
        }
    }

    // MARK: Connecting

    public func connect(to host: URL, displayName: String) async throws -> ConnectResult {
        let client = clientFactory(host)
        let status = try await client.authStatus()

        self.client = client
        let connection = SavedConnection(host: host,
                                         displayName: displayName,
                                         defaultPanelRef: saved?.host == host ? saved?.defaultPanelRef : nil)
        persist(connection)

        if status.setupRequired { return .needsSetup }
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
                return .ready
            } catch {
                return .needsSignIn
            }
        }
        return .needsSignIn
    }

    public func signIn(username: String, password: String) async throws {
        guard let client, let saved else { throw FiestaError.transport("not connected") }
        try await client.login(username: username, password: password)
        defaults.set(false, forKey: Keys.signedOut)
        // A credential the board just accepted makes the silent path
        // trustworthy again.
        silentLoginBlockedUntil = nil
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
        guard let client, let saved else { throw FiestaError.transport("not connected") }
        do {
            return try await operation(client)
        } catch FiestaError.unauthorized {
            guard let stored = credentials.load(for: saved.host.absoluteString),
                  !silentLoginIsBlocked else {
                throw FiestaError.unauthorized
            }
            do {
                try await client.login(username: stored.username, password: stored.password)
            } catch {
                silentLoginBlockedUntil = clock().addingTimeInterval(Self.rejectedCredentialCooldown)
                throw error
            }
            silentLoginBlockedUntil = nil
            return try await operation(client)
        }
    }

    private var silentLoginIsBlocked: Bool {
        guard let until = silentLoginBlockedUntil else { return false }
        if clock() < until { return true }
        silentLoginBlockedUntil = nil
        return false
    }

    // MARK: Preferences

    public func setDefaultPanel(ref: String?) {
        guard var connection = saved else { return }
        connection.defaultPanelRef = ref
        persist(connection)
    }

    public func signOut() {
        guard let saved else { return }
        try? credentials.delete(for: saved.host.absoluteString)
        clearCookies(for: saved.host)
        defaults.set(true, forKey: Keys.signedOut)
    }

    public func forget() {
        if let saved {
            try? credentials.delete(for: saved.host.absoluteString)
            clearCookies(for: saved.host)
        }
        defaults.removeObject(forKey: Keys.connection)
        defaults.removeObject(forKey: Keys.signedOut)
        self.saved = nil
        self.client = nil
    }

    private func clearCookies(for host: URL) {
        for cookie in HTTPCookieStorage.shared.cookies(for: host) ?? [] {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private func persist(_ connection: SavedConnection) {
        saved = connection
        if let data = try? JSONEncoder().encode(connection) {
            defaults.set(data, forKey: Keys.connection)
        }
    }
}
