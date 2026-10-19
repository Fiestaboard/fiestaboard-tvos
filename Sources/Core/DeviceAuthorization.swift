import Foundation

public struct TVSignInCapability: Decodable, Equatable, Sendable {
    public let supported: Bool
    public let enabled: Bool
    public let protocolVersion: Int
    public var isEnabled: Bool { supported && enabled && protocolVersion == 1 }
    enum CodingKeys: String, CodingKey { case supported, enabled, protocolVersion = "protocol_version" }
}

public struct DeviceChallenge: Decodable, Equatable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationPath: String
    public let verificationPathComplete: String
    public let expiresIn: TimeInterval
    public let interval: TimeInterval
    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code", userCode = "user_code"
        case verificationPath = "verification_path", verificationPathComplete = "verification_path_complete"
        case expiresIn = "expires_in", interval
    }

    /// Protocol v1 has exactly one activation route. Never let response paths
    /// redirect a person (or disclose even the public code) to another server.
    public func verificationURLs(baseURL: URL) throws -> (manual: URL, complete: URL) {
        let alphabet = Set("BCDFGHJKLMNPQRSTVWXYZ23456789")
        let code = userCode.replacingOccurrences(of: "-", with: "")
        guard code.count == 8, code.allSatisfy({ alphabet.contains($0) }),
              verificationPath == "/activate",
              verificationPathComplete == "/activate?user_code=\(userCode)",
              expiresIn > 0, interval > 0 else { throw DeviceCredentialError.invalidResponse }
        let normalized = FiestaClient.normalizedBaseURL(baseURL)
        guard let manual = URL(string: normalized.absoluteString + verificationPath),
              let complete = URL(string: normalized.absoluteString + verificationPathComplete) else {
            throw DeviceCredentialError.invalidResponse
        }
        return (manual, complete)
    }
}

public struct DeviceTokenResult: Decodable, Equatable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: TimeInterval
    public let sessionID: String
    public let scope: String
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", tokenType = "token_type", expiresIn = "expires_in"
        case sessionID = "session_id", scope
    }
    public func credential(now: Date) throws -> StoredCredential {
        guard accessToken.hasPrefix("fb_tv_"), !accessToken.contains(where: { $0.isWhitespace }),
              tokenType == "Bearer", scope == "tv_panels", !sessionID.isEmpty,
              expiresIn > 0, expiresIn <= 31_536_000 else { throw DeviceCredentialError.invalidResponse }
        return .deviceToken(accessToken: accessToken, sessionID: sessionID, expiresAt: now.addingTimeInterval(expiresIn))
    }
}

public struct DevicePollError: Error, Equatable, Sendable {
    public let code: String
    public let retryAfter: TimeInterval?
    public let status: Int
    public init(code: String, retryAfter: TimeInterval? = nil, status: Int = 400) {
        self.code = code; self.retryAfter = retryAfter; self.status = status
    }
    public var userMessage: String {
        switch code {
        case "authorization_pending": return "Waiting for you to allow this TV in your browser."
        case "slow_down", "rate_limited": return "The board asked this TV to wait. Trying again shortly."
        case "access_denied": return "This sign-in was denied. Choose New code to try again."
        case "expired_token": return "This code expired. Choose New code."
        case "invalid_grant": return "This code was cancelled or already used. Choose New code."
        case "feature_disabled": return "TV sign-in is disabled. Enable TV sign-in in your board's Account settings."
        case "session_limit": return "The board has too many signed-in devices. Revoke one in Account settings, then try again."
        default: return "The board couldn't complete this sign-in. Try a new code."
        }
    }
}

public enum DeviceCredentialError: Error, Equatable {
    case storageFailed, invalidResponse
    public var userMessage: String {
        switch self {
        case .storageFailed: return "This Apple TV couldn't securely save your sign-in. Try again."
        case .invalidResponse: return "The board returned an unsupported TV sign-in response. Update the board and try again."
        }
    }
}

/// Block every redirect, including same-host path escapes. A sign-in may contain
/// cookies, a password or a bearer; no automatic redirect is necessary here.
final class NoCredentialRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

extension FiestaClient {
    public func beginDeviceSignIn(deviceName: String, appVersion: String) async throws -> DeviceChallenge {
        let result: DeviceChallenge = try await deviceRequest(path: "/auth/device/authorize", body: metadata(deviceName, appVersion))
        _ = try result.verificationURLs(baseURL: baseURL)
        return result
    }
    public func pollDeviceSignIn(deviceCode: String) async throws -> DeviceTokenResult {
        try await deviceRequest(path: "/auth/device/token", body: ["device_code": deviceCode, "client_id": "fiestaboard-tvos"])
    }
    public func cancelDeviceSignIn(deviceCode: String) async throws {
        _ = try await send(method: "POST", path: "/auth/device/cancel", body: ["device_code": deviceCode, "client_id": "fiestaboard-tvos"], deviceEndpoint: true)
    }
    public func loginDevice(username: String, password: String, deviceName: String, appVersion: String) async throws -> DeviceTokenResult {
        var body = metadata(deviceName, appVersion)
        body["username"] = username; body["password"] = password
        return try await deviceRequest(path: "/auth/device/login", body: body)
    }
    public func revokeDeviceSession() async throws {
        _ = try await send(method: "DELETE", path: "/auth/device/session", body: nil, deviceEndpoint: true)
    }
    private func metadata(_ name: String, _ version: String) -> [String: Any] {
        ["client_id": "fiestaboard-tvos", "device_name": String(name.prefix(80)), "app_version": String(version.prefix(40))]
    }
    private func deviceRequest<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        let data = try await send(method: "POST", path: path, body: body, deviceEndpoint: true)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw DeviceCredentialError.invalidResponse }
    }
}
