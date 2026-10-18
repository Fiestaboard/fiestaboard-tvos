import XCTest
@testable import FiestaBoardTV

@MainActor
final class FiestaBotModelTests: XCTestCase {
    private func model() -> FiestaBotModel {
        FiestaBotModel(app: AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!, credentials: InMemoryCredentialStore())))
    }

    func testToolResultsAreReplayedWithoutTurningThemIntoUserInstructions() {
        let bot = model()
        bot.beginReply()
        bot.receive(.init(name: "text", data: .object(["delta": .string("Creating it.")])))
        bot.receive(.init(name: "tool_call", data: .object([
            "id": .string("call1"), "name": .string("create_page"), "title": .string("Create page"),
            "args": .object(["name": .string("Welcome")])
        ])))
        bot.receive(.init(name: "tool_result", data: .object([
            "id": .string("call1"), "status": .string("ok"), "summary": .string("Created"),
            "result": .object(["page_id": .string("page1")])
        ])))
        XCTAssertEqual(bot.currentPage?["id"]?.stringValue, "page1")
        XCTAssertNil(bot.currentPage?["template"], "No fabricated empty page content")
        let wire = bot.wireMessages()
        XCTAssertEqual(wire.map(\.role), ["assistant", "tool"])
        XCTAssertEqual(wire.first?.toolCalls?.first?.name, "create_page")
        XCTAssertEqual(wire.last?.toolCallId, "call1")
        XCTAssertEqual(wire.last?.result?["page_id"]?.stringValue, "page1")
    }

    func testApprovalAppearsOnlyWhenServerActuallyPauses() {
        let bot = model()
        bot.beginReply()
        bot.receive(.init(name: "tool_call", data: .object([
            "id": .string("call1"), "name": .string("delete_page"), "requires_approval": .bool(true)
        ])))
        XCTAssertNil(bot.pendingApproval)
        bot.receive(.init(name: "done", data: .object([
            "reason": .string("awaiting_approval"), "pending_tool_call_id": .string("call1")
        ])))
        XCTAssertEqual(bot.pendingApproval?.id, "call1")
        XCTAssertEqual(bot.wireMessages(awaiting: "call1").count, 1)
    }

    func testInterruptedActionsStayInTranscriptAndAreNotClaimedSuccessful() {
        let bot = model()
        bot.beginReply()
        bot.receive(.init(name: "tool_call", data: .object([
            "id": .string("call1"), "name": .string("create_page")
        ])))
        bot.finishInterrupted(message: "Connection lost")
        XCTAssertEqual(bot.entries.last?.tools.first?.phase, "interrupted")
        XCTAssertEqual(bot.wireMessages().last?.status, "interrupted")
        XCTAssertFalse(bot.isRunning)
        XCTAssertNotNil(bot.errorMessage)
    }

    func testQuestionOptionsAndContinueComeFromServer() {
        let bot = model()
        bot.beginReply()
        bot.receive(.init(name: "elicitation", data: .object([
            "id": .string("q1"), "message": .string("Which color?"), "allow_free_text": .bool(false),
            "requested_schema": .object(["properties": .object([
                "answer": .object(["enum": .array([.string("Blue"), .string("Red")])])
            ])])
        ])))
        bot.receive(.init(name: "done", data: .object([
            "reason": .string("awaiting_input"), "pending_tool_call_id": .string("q1")
        ])))
        XCTAssertEqual(bot.pendingQuestion?.options, ["Blue", "Red"])
        XCTAssertEqual(bot.pendingQuestion?.allowsFreeText, false)
        bot.receive(.init(name: "done", data: .object(["reason": .string("step_limit")])))
        XCTAssertTrue(bot.canContinue)
    }

    private func pausedQuestion(_ bot: FiestaBotModel) {
        bot.beginReply()
        bot.receive(.init(name: "tool_call", data: .object(["id": .string("q1"), "name": .string("ask_user")])))
        bot.receive(.init(name: "elicitation", data: .object(["id": .string("q1"), "message": .string("Color?"), "allow_free_text": .bool(true)])))
        bot.receive(.init(name: "done", data: .object(["reason": .string("awaiting_input"), "pending_tool_call_id": .string("q1")])))
    }

    func testAcceptedAnswerIsPreservedInNextTurnWithoutToolResultEvent() {
        let bot = model()
        pausedQuestion(bot)
        bot.beginReply(answering: .init(toolCallId: "q1", decision: "answer", answer: .init(action: "accept", content: ["answer": .string("Blue")])))
        bot.receive(.init(name: "status", data: .object(["phase": .string("thinking")])))
        bot.receive(.init(name: "done", data: .object(["reason": .string("complete")])))
        let result = bot.wireMessages().first { $0.toolCallId == "q1" }
        XCTAssertEqual(result?.status, "answered")
        XCTAssertEqual(result?.result?["answer"]?.stringValue, "Blue")
        XCTAssertNil(bot.pendingQuestion)
    }

    func testUnconfirmedApprovalCannotBeResubmittedAfterInterruption() {
        let bot = model()
        bot.beginReply()
        bot.receive(.init(name: "tool_call", data: .object(["id": .string("c1"), "name": .string("delete_page")])))
        bot.receive(.init(name: "done", data: .object(["reason": .string("awaiting_approval"), "pending_tool_call_id": .string("c1")])))
        bot.beginReply(answering: .init(toolCallId: "c1", decision: "approve"))
        bot.finishInterrupted(message: "Connection lost before status arrived")
        XCTAssertNil(bot.pendingApproval)
        XCTAssertEqual(bot.wireMessages().first { $0.toolCallId == "c1" }?.status, "interrupted")
    }

    func testRejectedAnswerRemainsAvailableForCorrection() {
        let bot = model()
        pausedQuestion(bot)
        bot.beginReply(answering: .init(toolCallId: "q1", decision: "answer", answer: .init(action: "accept", content: ["answer": .string("Blue")])))
        bot.finishInterrupted(message: "Invalid option", decisionMayHaveRun: false)
        XCTAssertEqual(bot.pendingQuestion?.id, "q1")
        XCTAssertFalse(bot.wireMessages().contains { $0.toolCallId == "q1" })
    }

    func testOpeningBotAndReturningPreservesViewerOrigin() {
        let app = AppModel(connection: ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                                       credentials: InMemoryCredentialStore()))
        app.openPanel(ref: "1")
        app.showFiestaBot()
        XCTAssertEqual(app.route, .fiestaBot)
        app.dismissFiestaBot()
        XCTAssertEqual(app.route, .viewer("1"))
        app.route = .signIn
        XCTAssertNil(app.fiestaBot)
    }
}
