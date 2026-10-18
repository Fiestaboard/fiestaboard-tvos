import XCTest
@testable import FiestaBoardTV

final class FiestaChatTests: XCTestCase {
    func testTVAvailabilityRequiresExplicitServerCapability() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let client = FiestaClient(baseURL: URL(string: "http://board.local")!, session: StubURLProtocol.makeSession())
        for (extra, supported) in [("", false), (",\"tv_chat_supported\":false", false), (",\"tv_chat_supported\":true", true)] {
            StubURLProtocol.enqueue(.json("{\"enabled\":true,\"providers\":[{\"id\":\"p\"}]\(extra)}"), for: "/settings/ai")
            let availability = try await client.aiAvailability()
            XCTAssertTrue(availability.enabled)
            XCTAssertTrue(availability.configured)
            XCTAssertEqual(availability.supportsTV, supported)
        }
    }

    func testSSEPreservesSplitUTF8AndCRLFFrames() throws {
        var parser = ChatSSEParser()
        let bytes = Data(": keepalive\r\nevent: text\r\ndata: {\"delta\":\"Café ☀\"}\r\n\r\nevent: done\ndata: {\"reason\":\"complete\"}\n\n".utf8)
        var events: [ChatEvent] = []
        for byte in bytes { events += try parser.append(Data([byte])) }
        XCTAssertEqual(events.map(\.name), ["text", "done"])
        XCTAssertEqual(events.first?.data["delta"]?.stringValue, "Café ☀")
    }

    func testSSEJoinsDataLinesAndRejectsMalformedPayload() throws {
        var parser = ChatSSEParser()
        let events = try parser.append(Data("event: text\ndata: {\ndata: \"delta\":\"hello\"}\n\n".utf8))
        XCTAssertEqual(events.first?.data["delta"], .string("hello"))
        XCTAssertThrowsError(try parser.append(Data("event: text\ndata: nope\n\n".utf8)))
    }

    func testStructuredRequestPreservesToolResultsAndUnresolvedApproval() throws {
        let call = ChatToolCallRecord(id: "c1", name: "delete_page", args: ["page_id": .string("p1")])
        let request = ChatRequest(messages: [
            ChatWireMessage(role: "user", content: "Delete this page"),
            ChatWireMessage(role: "assistant", toolCalls: [call])
        ], boardId: "tv-board", resume: ChatResume(toolCallId: "c1", decision: "deny"))
        let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(json["board_id"], .string("tv-board"))
        XCTAssertEqual(json["interaction_mode"], .string("tv"))
        XCTAssertEqual(json["resume"]?["tool_call_id"], .string("c1"))
        XCTAssertEqual(json["messages"]?.arrayValue?.count, 2)
        XCTAssertEqual(try JSONDecoder().decode(ChatRequest.self, from: JSONEncoder().encode(request)), request)
    }

    func testStreamEOFIsInterruptedAndDoesNotReplay() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.enqueue(.init(body: Data("event: tool_call\ndata: {\"id\":\"c1\",\"name\":\"create_page\"}\n\n".utf8), headers: ["Content-Type":"text/event-stream"]), for: "/pages/ai/chat")
        let client = FiestaClient(baseURL: URL(string: "http://board.local")!, session: StubURLProtocol.makeSession())
        let stream = try await client.chat(ChatRequest(messages: [.init(role: "user", content: "Make a page")], boardId: "tv"))
        var names: [String] = []
        do {
            for try await event in stream { names.append(event.name) }
            XCTFail("A missing terminal event must fail")
        } catch ChatStreamError.interrupted { }
        XCTAssertEqual(names, ["tool_call"])
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testInitial401CanBeRecoveredBeforeStreamStarts() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.enqueue(.json("{}", status: 401), for: "/pages/ai/chat")
        let client = FiestaClient(baseURL: URL(string: "http://board.local")!, session: StubURLProtocol.makeSession())
        do {
            _ = try await client.chat(ChatRequest(messages: [.init(role: "user", content: "Hello")], boardId: nil))
            XCTFail("Expected initial unauthorized")
        } catch FiestaError.unauthorized { }
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testHTTPRejectionsPreserveStatusForApprovalRecovery() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let client = FiestaClient(baseURL: URL(string: "http://board.local")!, session: StubURLProtocol.makeSession())
        for status in [400, 404, 409, 422, 500, 503] {
            StubURLProtocol.enqueue(.json("{\"detail\":\"Rejected request\"}", status: status), for: "/pages/ai/chat")
            do {
                _ = try await client.chat(ChatRequest(messages: [.init(role: "user", content: "Hello")], boardId: "tv"))
                XCTFail("Expected rejection")
            } catch ChatStreamError.rejected(let receivedStatus, let message) {
                XCTAssertEqual(receivedStatus, status)
                XCTAssertEqual(message, "Rejected request")
            }
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 6)
    }
}
