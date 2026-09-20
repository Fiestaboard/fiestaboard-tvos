import Foundation

/// HTTP client for a FiestaBoard instance.
///
/// Deliberately thin: no retry, no caching, no request coalescing. The
/// polling cadence in `PanelStore` is the retry policy, and layering a
/// second one underneath it only multiplies requests during an outage.
public final class FiestaClient: @unchecked Sendable {

    public let baseURL: URL
    private let session: URLSession
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
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = HTTPCookieStorage.shared
            config.httpShouldSetCookies = true
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
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
                            animationsEnabled: Bool? = nil) async throws -> PanelUpdateResult {
        var body: [String: Any] = [:]
        // Only send what was asked for: PanelUpdate treats every field as
        // optional, and sending nulls would clear settings we never touched.
        if let diagonal { body["screen_diagonal_inches"] = diagonal }
        if let aspectW { body["screen_aspect_w"] = aspectW }
        if let aspectH { body["screen_aspect_h"] = aspectH }
        if let calibration { body["calibration_scale"] = calibration }
        if let animationsEnabled { body["animations_enabled"] = animationsEnabled }

        let data = try await send(method: "PATCH", path: "/panels/\(id)", body: body)
        struct Envelope: Decodable {
            let panel: Panel
            let incompatibleReferences: [IncompatibleReference]?
            enum CodingKeys: String, CodingKey {
                case panel
                case incompatibleReferences = "incompatible_references"
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

    private func url(for path: String) -> URL {
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
        default:
            throw FiestaError.http(http.statusCode)
        }
    }

    private static func detail(from data: Data) -> String? {
        struct Detail: Decodable { let detail: String? }
        return try? JSONDecoder().decode(Detail.self, from: data).detail
    }
}
