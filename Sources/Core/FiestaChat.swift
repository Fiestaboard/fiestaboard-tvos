import Foundation

/// Lossless structure for tool arguments/results, including future tool names.
public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue? { objectValue?[key] }
    public var objectValue: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    public var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    public var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var numberValue: Double? { if case .number(let v) = self { return v }; return nil }
}

public struct ChatToolCallRecord: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var args: [String: JSONValue]
    public init(id: String, name: String, args: [String: JSONValue] = [:]) {
        self.id = id; self.name = name; self.args = args
    }
}

public struct ChatWireMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: String
    public var toolCalls: [ChatToolCallRecord]?
    public var toolCallId: String?
    public var name: String?
    public var status: String?
    public var result: JSONValue?
    enum CodingKeys: String, CodingKey {
        case role, content, name, status, result
        case toolCalls = "tool_calls", toolCallId = "tool_call_id"
    }
    public init(role: String, content: String = "", toolCalls: [ChatToolCallRecord]? = nil,
                toolCallId: String? = nil, name: String? = nil, status: String? = nil, result: JSONValue? = nil) {
        self.role = role; self.content = content; self.toolCalls = toolCalls; self.toolCallId = toolCallId
        self.name = name; self.status = status; self.result = result
    }
}

public struct ChatAnswer: Codable, Equatable, Sendable {
    public var action: String
    public var content: [String: JSONValue]?
    public init(action: String, content: [String: JSONValue]? = nil) { self.action = action; self.content = content }
}
public struct ChatResume: Codable, Equatable, Sendable {
    public var toolCallId: String
    public var decision: String
    public var answer: ChatAnswer?
    enum CodingKeys: String, CodingKey { case toolCallId = "tool_call_id", decision, answer }
    public init(toolCallId: String, decision: String, answer: ChatAnswer? = nil) {
        self.toolCallId = toolCallId; self.decision = decision; self.answer = answer
    }
}
public struct ChatRequest: Codable, Equatable, Sendable {
    public var messages: [ChatWireMessage]
    public var boardId: String?
    public var resume: ChatResume?
    public var currentPage: JSONValue?
    public var surface: String = "global"
    public var interactionMode: String = "tv"
    // Compatibility with existing servers. Board context is resolved server-side.
    public var deviceType: String = "flagship"
    enum CodingKeys: String, CodingKey {
        case messages, resume, surface, interactionMode = "interaction_mode"
        case boardId = "board_id", currentPage = "current_page", deviceType = "device_type"
    }
    public init(messages: [ChatWireMessage], boardId: String?, resume: ChatResume? = nil, currentPage: JSONValue? = nil) {
        self.messages = messages; self.boardId = boardId; self.resume = resume; self.currentPage = currentPage
    }
}

public struct ChatEvent: Equatable, Sendable {
    public let name: String
    public let data: JSONValue
    public init(name: String, data: JSONValue) { self.name = name; self.data = data }
}

public enum ChatStreamError: Error, LocalizedError, Equatable {
    case interrupted, invalidEvent, response(String)
    /// Status distinguishes validation refusal from an uncertain server failure.
    /// A 5xx is never proof that a submitted approval did not execute.
    case rejected(status: Int, message: String)
    public var errorDescription: String? {
        switch self {
        case .interrupted: return "The connection ended before FiestaBot finished. An action already started may have completed."
        case .invalidEvent: return "FiestaBot returned an unreadable response."
        case .response(let message): return message
        case .rejected(_, let message): return message
        }
    }
}

/// Incremental UTF-8 SSE framing; a byte may arrive in any network chunk.
public struct ChatSSEParser {
    private var line = Data()
    private var eventName = ""
    private var dataLines: [String] = []
    private var afterCR = false
    private var frameBytes = 0
    public init() {}
    public mutating func append(_ bytes: Data) throws -> [ChatEvent] {
        var events: [ChatEvent] = []
        for byte in bytes {
            if afterCR { afterCR = false; if byte == 10 { continue } }
            if byte == 10 || byte == 13 {
                if let event = try finishLine() { events.append(event) }
                afterCR = byte == 13
            } else {
                line.append(byte); frameBytes += 1
                guard frameBytes <= 8 * 1024 * 1024 else { throw ChatStreamError.invalidEvent }
            }
        }
        return events
    }
    private mutating func finishLine() throws -> ChatEvent? {
        guard let text = String(data: line, encoding: .utf8) else { throw ChatStreamError.invalidEvent }
        line.removeAll(keepingCapacity: true)
        if text.isEmpty {
            defer { eventName = ""; dataLines = []; frameBytes = 0 }
            guard !eventName.isEmpty, !dataLines.isEmpty else { return nil }
            guard let data = dataLines.joined(separator: "\n").data(using: .utf8),
                  let payload = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                throw ChatStreamError.invalidEvent
            }
            return ChatEvent(name: eventName, data: payload)
        }
        if text.hasPrefix(":") { return nil }
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let value = parts.count > 1 ? String(parts[1]).dropFirst(parts[1].hasPrefix(" ") ? 1 : 0) : ""[...]
        if parts[0] == "event" { eventName = String(value) }
        if parts[0] == "data" { dataLines.append(String(value)) }
        return nil
    }
}

public struct AIAvailability: Equatable, Sendable {
    public let enabled: Bool
    public let configured: Bool
    public let supportsTV: Bool
    public init(enabled: Bool, configured: Bool, supportsTV: Bool = false) {
        self.enabled = enabled; self.configured = configured; self.supportsTV = supportsTV
    }
}
public struct ChatPage: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let deviceType: String
    public let gridRows: Int?
    public let gridCols: Int?
    enum CodingKeys: String, CodingKey { case id, name, deviceType = "device_type", gridRows = "grid_rows", gridCols = "grid_cols" }
}
public struct ChatPageSendResult: Decodable, Sendable {
    public let pageId: String
    public let message: String
    public let sentToBoard: Bool
    public let paused: Bool
    enum CodingKeys: String, CodingKey { case message, paused, pageId = "page_id", sentToBoard = "sent_to_board" }
}
