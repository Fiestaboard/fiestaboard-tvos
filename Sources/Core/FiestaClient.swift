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

    public init(baseURL: URL, session: URLSession? = nil) {
        // Normalising here means every caller can pass whatever the user typed.
        var normalized = baseURL.absoluteString
        while normalized.hasSuffix("/") { normalized.removeLast() }
        if normalized.hasSuffix("/api") { normalized.removeLast(4) }
        self.baseURL = URL(string: normalized) ?? baseURL

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
        try await get("/panel/\(ref)")
    }

    public func frame(ref: String) async throws -> PanelFrame {
        try await get("/panel/\(ref)/frame")
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
        let data = try await send(method: "PATCH", path: "/panels/\(id)", body: body)
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
    private func send(method: String, path: String, body: [String: Any]?) async throws -> Data {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FiestaError.transport("\(error)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw FiestaError.transport("non-HTTP response")
        }

        switch http.statusCode {
        case 200..<300:
            return data
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
