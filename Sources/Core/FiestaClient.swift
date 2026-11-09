import Foundation

/// HTTP client for a FiestaBoard instance.
///
/// Deliberately thin: no retry, no caching, no request coalescing. The
/// polling cadence in `PanelStore` is the retry policy, and layering a
/// second one underneath it only multiplies requests during an outage.
public final class FiestaClient: @unchecked Sendable {

    public let baseURL: URL
    let session: URLSession
    private let decoder = JSONDecoder()
    private let tokenLock = NSLock()
    private var storedDeviceToken: String?
    let redirectGuard = NoCredentialRedirects()
    public var deviceToken: String? { tokenLock.withLock { storedDeviceToken } }
    public func setDeviceToken(_ token: String?) {
        tokenLock.withLock { storedDeviceToken = token }
        if token != nil {
            for cookie in session.configuration.httpCookieStorage?.cookies ?? [] {
                session.configuration.httpCookieStorage?.deleteCookie(cookie)
            }
        }
    }
    public static func normalizedBaseURL(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        c.scheme = c.scheme?.lowercased(); c.host = c.host?.lowercased()
        if (c.scheme == "http" && c.port == 80) || (c.scheme == "https" && c.port == 443) { c.port = nil }
        c.query = nil; c.fragment = nil; c.user = nil; c.password = nil
        while c.path.hasSuffix("/") { c.path.removeLast() }
        if c.path.hasSuffix("/api") { c.path.removeLast(4) }
        return c.url ?? url
    }
    func requireLegacyPermission() throws {
        guard deviceToken == nil else { throw FiestaError.http(403) }
    }

    public init(baseURL: URL, session: URLSession? = nil) {
        // Normalising here means every caller can pass whatever the user typed.
        self.baseURL = Self.normalizedBaseURL(baseURL)

        if let session {
            self.session = session
        } else {
            // Cookies belong to this connection. A late login response from
            // a forgotten client must never authenticate its replacement.
            // Keychain credentials provide recovery after an app restart.
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = true
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            // 10s, not URLSession's default 60. The board is a Raspberry Pi
            // one hop away, so anything slower than this is a board that is
            // off — and a TV showing a frozen spinner for a full minute
            // reads as a hung app to someone holding a remote.
            config.timeoutIntervalForRequest = 10
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: Endpoints

    public func authStatus() async throws -> AuthStatus {
        try await get("/auth/status")
    }

    public func login(username: String, password: String) async throws {
        // remember_me is always true: a 7-day session on a wall-mounted TV
        // means a password prompt on a Siri Remote every week.
        let body: [String: Any] = ["username": username,
                                   "password": password,
                                   "remember_me": true]
        _ = try await send(method: "POST", path: "/auth/login", body: body)
    }

    public func panels() async throws -> [Panel] {
        struct Envelope: Decodable { let panels: [Panel] }
        let envelope: Envelope = try await get("/panels")
        return envelope.panels
    }

    /// `ref` is a panel id or its short code, so "1" is valid.
    public func panel(ref: String) async throws -> Panel {
        try await get("/panel/\(Self.pathSegment(ref))")
    }

    /// The panel plus the hub's clock from the same response (A6a).
    ///
    /// `GET /panel/{id}` is sent `Cache-Control: no-store`, so its `Date`
    /// header is the hub's own: the status chip counts an override down on
    /// that clock, not on a TV whose clock may be minutes out. Nil when the
    /// header is missing or does not parse.
    public func panelReading(ref: String) async throws -> PanelReading {
        let (data, response) = try await exchange(method: "GET", path: "/panel/\(Self.pathSegment(ref))", body: nil)
        do {
            return PanelReading(panel: try decoder.decode(Panel.self, from: data),
                                hubDate: response.value(forHTTPHeaderField: "Date").flatMap(Self.httpDate))
        } catch {
            throw FiestaError.decoding("\(error)")
        }
    }

    /// An HTTP `Date` (RFC 9110 IMF-fixdate, e.g. "Sun, 08 Nov 2026 02:18:00 GMT").
    static func httpDate(_ value: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: value.trimmingCharacters(in: .whitespaces))
    }

    public func frame(ref: String) async throws -> PanelFrame {
        try await get("/panel/\(Self.pathSegment(ref))/frame")
    }

    public func updatePanel(id: String,
                            diagonal: Double? = nil,
                            aspectW: Double? = nil,
                            aspectH: Double? = nil,
                            calibration: Double? = nil,
                            animationsEnabled: Bool? = nil,
                            renderStyle: PanelRenderStyle? = nil) async throws -> PanelUpdateResult {
        var body: [String: Any] = [:]
        // Only send what was asked for: PanelUpdate treats every field as
        // optional, and sending nulls would clear settings we never touched.
        if let diagonal { body["screen_diagonal_inches"] = diagonal }
        if let aspectW { body["screen_aspect_w"] = aspectW }
        if let aspectH { body["screen_aspect_h"] = aspectH }
        if let calibration { body["calibration_scale"] = calibration }
        if let animationsEnabled { body["animations_enabled"] = animationsEnabled }
        if let renderStyle { body["render_style"] = renderStyle.rawValue }

        return try await updatePanel(id: id, body: body)
    }

    func updatePanel(id: String, patch: PanelSettingsPatch) async throws -> PanelUpdateResult {
        let result = try await updatePanel(id: id, body: patch.body)
        try patch.verifyApplied(to: result.panel)
        return result
    }

    private func updatePanel(id: String, body: [String: Any]) async throws -> PanelUpdateResult {
        let data = try await send(method: "PATCH", path: "/panels/\(Self.pathSegment(id))", body: body)
        struct Envelope: Decodable {
            let panel: Panel
            let incompatibleReferences: [IncompatibleReference]?
            enum CodingKeys: String, CodingKey {
                case panel
                case incompatibleReferences = "incompatible_references"
            }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                // Current servers return PanelUpdateResponse at the top level.
                // Also accept the wrapped shape used by earlier client fixtures.
                panel = try container.contains(.panel)
                    ? container.decode(Panel.self, forKey: .panel)
                    : Panel(from: decoder)
                incompatibleReferences = try container.decodeIfPresent(
                    [IncompatibleReference].self, forKey: .incompatibleReferences)
            }
        }
        do {
            let envelope = try decoder.decode(Envelope.self, from: data)
            return PanelUpdateResult(panel: envelope.panel,
                                     incompatibleReferences: envelope.incompatibleReferences ?? [])
        } catch {
            throw FiestaError.decoding("\(error)")
        }
    }

    // MARK: Plumbing

    /// Unreserved ASCII only: letters, digits, `-` and `_`.
    private static let segmentAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    /// One path segment (#24 S3). Anything outside the hub's id alphabet is
    /// percent-encoded, `.` included, so a ref can't add a query, a fragment,
    /// another segment or a dot-segment. Hub ids and short codes pass through.
    static func pathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? ""
    }

    func url(for path: String) -> URL {
        // The Docker/nginx public port proxies /api/* to FastAPI after
        // stripping that prefix. Direct /auth/* URLs reach the web UI.
        URL(string: baseURL.absoluteString + "/api" + path) ?? baseURL
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(method: "GET", path: path, body: nil)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw FiestaError.decoding("\(error)")
        }
    }

    @discardableResult
    func send(method: String, path: String, body: [String: Any]?, deviceEndpoint: Bool = false) async throws -> Data {
        try await exchange(method: method, path: path, body: body, deviceEndpoint: deviceEndpoint).data
    }

    /// `send`, keeping the response for its headers.
    func exchange(method: String, path: String, body: [String: Any]?,
                  deviceEndpoint: Bool = false) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
        if let token = deviceToken {
            let parts = path.split(separator: "/")
            let panelRead = method == "GET" && parts.first == "panel" &&
                (parts.count == 2 || (parts.count == 3 && parts.last == "frame"))
            let panelPatch = method == "PATCH" && parts.count == 2 && parts.first == "panels"
            let allowed = (method == "GET" && ["/auth/status", "/panels"].contains(path)) ||
                (method == "DELETE" && path == "/auth/device/session") || panelRead || panelPatch
            guard allowed, !path.contains(".."), !path.contains("%"), !path.contains("?"), !path.contains("#") else { throw FiestaError.http(403) }
            if panelPatch {
                let fields: Set<String> = ["screen_diagonal_inches", "screen_aspect_w", "screen_aspect_h", "calibration_scale", "animations_enabled", "render_style"]
                guard Set(body?.keys.map { $0 } ?? []).isSubset(of: fields) else { throw FiestaError.http(403) }
            }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.httpShouldHandleCookies = false
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: redirectGuard)
        } catch {
            throw FiestaError.transport("\(error)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw FiestaError.transport("non-HTTP response")
        }

        if deviceEndpoint && !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 { throw FiestaError.unauthorized }
            if http.statusCode == 503 { throw FiestaError.unavailable }
            struct Payload: Decodable { let error: String }
            let code = (try? JSONDecoder().decode(Payload.self, from: data).error) ?? "http_\(http.statusCode)"
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw DevicePollError(code: code, retryAfter: retry, status: http.statusCode)
        }
        switch http.statusCode {
        case 200..<300:
            return (data, http)
        case 401:
            throw FiestaError.unauthorized
        case 404:
            throw FiestaError.notFound(Self.detail(from: data) ?? "Not found")
        case 409:
            // The middleware answers 409 for "no user provisioned yet".
            throw FiestaError.setupRequired
        case 503:
            // nginx answers 503 while FastAPI is still coming up — the normal
            // state for the first half-minute after a power cut. Falling
            // through to the generic 5xx told people to go and read the logs
            // of a board that was doing nothing wrong. Its detail is a fixed
            // string nginx writes itself, so it is not carried: see
            // `FiestaError.unavailable`.
            throw FiestaError.unavailable
        default:
            throw FiestaError.http(http.statusCode)
        }
    }

    private static func detail(from data: Data) -> String? {
        struct Detail: Decodable { let detail: String? }
        return try? JSONDecoder().decode(Detail.self, from: data).detail
    }
}
