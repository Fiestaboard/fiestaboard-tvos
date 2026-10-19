import Foundation

extension FiestaClient {
    /// Wait for headers before returning: only an initial HTTP 401 may be
    /// retried by ConnectionStore.authorized. Stream errors never replay a POST.
    public func chat(_ body: ChatRequest) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        try requireLegacyPermission()
        var request = URLRequest(url: url(for: "/pages/ai/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        let (bytes, response) = try await session.bytes(for: request, delegate: redirectGuard)
        guard let http = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw ChatStreamError.response("The board returned a non-HTTP response.")
        }
        if !(200..<300).contains(http.statusCode) {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= 65536 { break }
            }
            bytes.task.cancel()
            throw chatHTTPError(http.statusCode, data: data)
        }
        guard http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else {
            bytes.task.cancel()
            throw ChatStreamError.response("The board did not return a FiestaBot stream. Update FiestaBoard and try again.")
        }
        return AsyncThrowingStream { continuation in
            let reader = Task {
                do {
                    var parser = ChatSSEParser()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        for event in try parser.append(Data([byte])) {
                            continuation.yield(event)
                            if event.name == "done" || event.name == "error" {
                                continuation.finish()
                                bytes.task.cancel()
                                return
                            }
                        }
                    }
                    throw ChatStreamError.interrupted
                } catch {
                    continuation.finish(throwing: error)
                    bytes.task.cancel()
                }
            }
            continuation.onTermination = { @Sendable _ in
                reader.cancel()
                bytes.task.cancel()
            }
        }
    }

    public func aiAvailability() async throws -> AIAvailability {
        struct Settings: Decodable {
            let enabled: Bool
            let providers: [JSONValue]
            let supportsTV: Bool?
            enum CodingKeys: String, CodingKey { case enabled, providers, supportsTV = "tv_chat_supported" }
        }
        let settings: Settings = try await chatJSON(path: "/settings/ai")
        return AIAvailability(enabled: settings.enabled, configured: !settings.providers.isEmpty,
                              supportsTV: settings.supportsTV == true)
    }

    public func pages() async throws -> [ChatPage] {
        struct Pages: Decodable { let pages: [ChatPage] }
        let response: Pages = try await chatJSON(path: "/pages")
        return response.pages
    }

    /// One-off send; schedules and saved active-page selection stay intact.
    /// The caller explains that the normal schedule may replace the page.
    public func sendPage(id: String, boardId: String) async throws -> ChatPageSendResult {
        guard let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))) else {
            throw ChatStreamError.response("Invalid page identifier.")
        }
        return try await chatJSON(path: "/pages/\(escaped)/send", method: "POST",
                                  body: .object(["board_id": .string(boardId), "target": .string("board")]))
    }

    private func chatJSON<T: Decodable>(path: String, method: String = "GET", body: JSONValue? = nil) async throws -> T {
        try requireLegacyPermission()
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request, delegate: redirectGuard)
        guard let http = response as? HTTPURLResponse else { throw ChatStreamError.response("Invalid board response.") }
        guard (200..<300).contains(http.statusCode) else { throw chatHTTPError(http.statusCode, data: data) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func chatHTTPError(_ status: Int, data: Data) -> Error {
        if status == 401 { return FiestaError.unauthorized }
        if let payload = try? JSONDecoder().decode(JSONValue.self, from: data) {
            if let detail = payload["detail"]?.stringValue { return ChatStreamError.rejected(status: status, message: detail) }
            if let message = payload["message"]?.stringValue { return ChatStreamError.rejected(status: status, message: message) }
        }
        return ChatStreamError.rejected(status: status, message: "FiestaBoard returned HTTP \(status).")
    }
}
