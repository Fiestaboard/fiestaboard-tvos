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

    func testDisplayResultsOpenOnlyPanelsKnownToThisConnection() throws {
        let bot = model()
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        bot.panels = [panel]
        let tool = BotTool(id: "list", name: "list_panels", args: .object([:]), title: "Panels", phase: "ok",
                           result: .object(["panels": .array([.object(["id": .string(panel.id)]), .object(["id": .string("unknown")])])]))
        XCTAssertEqual(bot.panelsForTool(tool).map(\.id), [panel.id])
    }

    private func modelForPageSend() throws -> FiestaBotModel {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let saved = SavedConnection(host: URL(string: "http://board.local")!, displayName: "Board")
        defaults.set(try JSONEncoder().encode(saved), forKey: "fiestaboard.connection")
        let connection = ConnectionStore(defaults: defaults, credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        let bot = FiestaBotModel(app: AppModel(connection: connection))
        let panel = try JSONDecoder().decode(Panel.self, from: Data(Fixtures.panelJSON.utf8))
        bot.panels = [panel]
        bot.selectedPanelID = panel.id
        bot.pages = [try JSONDecoder().decode(ChatPage.self, from: Data(#"{"id":"pageB","name":"Weather","device_type":"panel","grid_rows":12,"grid_cols":30}"#.utf8))]
        bot.currentPage = .object(["id": .string("pageA"), "name": .string("Welcome")])
        return bot
    }

    func testShowingAnotherPageUpdatesTheNextChatContext() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let bot = try modelForPageSend()
        StubURLProtocol.enqueue(.json(#"{"page_id":"pageB","message":"WEATHER","sent_to_board":true,"paused":false}"#), for: "/pages/pageB/send")
        await bot.showPage("pageB")
        XCTAssertEqual(bot.currentPage?["id"]?.stringValue, "pageB")
        XCTAssertEqual(bot.currentPage?["name"]?.stringValue, "Weather")
        XCTAssertNil(bot.currentPage?["template"])
        XCTAssertNil(bot.errorMessage)
    }

    func testFailedOrPausedPageSendKeepsThePreviousChatContext() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let bot = try modelForPageSend()
        let previous = bot.currentPage
        for response in [
            StubURLProtocol.Stub.json(#"{"page_id":"pageB","message":"WEATHER","sent_to_board":false,"paused":true}"#),
            StubURLProtocol.Stub.json(#"{"detail":"Failed to send to board"}"#, status: 500)
        ] {
            StubURLProtocol.enqueue(response, for: "/pages/pageB/send")
            await bot.showPage("pageB")
            XCTAssertEqual(bot.currentPage, previous)
            XCTAssertNotNil(bot.errorMessage)
        }
    }

    func testScopedTVSignInRejectsProgrammaticBotNavigation() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let connection = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                         credentials: InMemoryCredentialStore(),
                                         clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled), for: "/api/auth/status")
        _ = try await connection.connect(to: URL(string: "http://board.test")!, displayName: "Board")
        let token = try JSONDecoder().decode(DeviceTokenResult.self, from: Data(DeviceAuthorizationTests.token.utf8))
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled.replacingOccurrences(of: "\"authenticated\":false", with: "\"authenticated\":true")), for: "/api/auth/status")
        try await connection.adoptDeviceCredential(token, expectedGeneration: connection.connectionGeneration)
        let app = AppModel(connection: connection)
        app.openPanel(ref: "1")
        XCTAssertFalse(app.showFiestaBot(), "A rejected navigation must tell the caller to keep viewing")
        XCTAssertEqual(app.route, .viewer("1"))
        XCTAssertNil(app.fiestaBot)
    }

    func testOpeningBotAndReturningPreservesViewerOrigin() {
        let app = AppModel(connection: ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                                       credentials: InMemoryCredentialStore()))
        app.openPanel(ref: "1")
        XCTAssertTrue(app.showFiestaBot())
        XCTAssertEqual(app.route, .fiestaBot)
        app.dismissFiestaBot()
        XCTAssertEqual(app.route, .viewer("1"))
        app.route = .signIn
        XCTAssertNil(app.fiestaBot)
    }

    func testAvailabilityRetryClearsThePreviousConnectionError() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let bot = try modelForPageSend()
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        StubURLProtocol.enqueue(.json(#"{"detail":"Temporarily unavailable"}"#, status: 503), for: "/settings/ai")
        await bot.load()
        XCTAssertNotNil(bot.errorMessage)

        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        StubURLProtocol.enqueue(.json(#"{"enabled":true,"providers":[{"name":"test"}],"tv_chat_supported":true}"#), for: "/settings/ai")
        await bot.load()

        XCTAssertTrue(bot.canSend)
        XCTAssertNil(bot.errorMessage)
        XCTAssertNil(bot.availabilityMessage)
    }

    func testFailedAvailabilityRefreshDisablesSending() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let bot = try modelForPageSend()
        bot.isAvailable = true
        XCTAssertTrue(bot.canSend)
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        StubURLProtocol.enqueue(.json(#"{"detail":"Temporarily unavailable"}"#, status: 503), for: "/settings/ai")

        await bot.load()

        XCTAssertFalse(bot.isAvailable)
        XCTAssertFalse(bot.canSend)
        XCTAssertNotNil(bot.availabilityMessage)
    }

    func testAvailabilityRefreshDisablesSendingUntilTheResponseArrives() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let bot = try modelForPageSend()
        bot.isAvailable = true
        let started = expectation(description: "availability request started")
        var release: (() -> Void)?
        var held = StubURLProtocol.Stub.json(#"{"enabled":true,"providers":[{"name":"test"}],"tv_chat_supported":true}"#)
        held.beforeReply = { reply in
            Task { @MainActor in release = reply; started.fulfill() }
        }
        StubURLProtocol.enqueue(.json(Fixtures.panelsList), for: "/api/panels")
        StubURLProtocol.enqueue(held, for: "/settings/ai")
        let loading = Task { await bot.load() }
        await fulfillment(of: [started], timeout: 2)

        XCTAssertTrue(bot.isLoading)
        XCTAssertFalse(bot.canSend)
        release?()
        await loading.value
        XCTAssertTrue(bot.canSend)
    }

    func testPageListFailureDoesNotReplaceTheConversationError() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let bot = try modelForPageSend()
        bot.errorMessage = "An action may have finished."
        StubURLProtocol.enqueue(.json(#"{"detail":"Pages unavailable"}"#, status: 503), for: "/pages")

        await bot.loadPages()

        XCTAssertEqual(bot.errorMessage, "An action may have finished.")
        guard case .failed(let message) = bot.pageLoadState else {
            return XCTFail("A failed page request must offer recovery instead of an empty library")
        }
        XCTAssertFalse(message.isEmpty)
        StubURLProtocol.enqueue(.json(#"{"pages":[]}"#), for: "/pages")
        await bot.loadPages()
        XCTAssertEqual(bot.pageLoadState, .loaded)
        XCTAssertTrue(bot.pages.isEmpty)
        XCTAssertEqual(bot.errorMessage, "An action may have finished.")
    }

    func testPageListLoadingDoesNotClaimTheLibraryIsEmpty() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let bot = try modelForPageSend()
        bot.pages = []
        let started = expectation(description: "page request started")
        var release: (() -> Void)?
        var held = StubURLProtocol.Stub.json(#"{"pages":[]}"#)
        held.beforeReply = { reply in
            Task { @MainActor in release = reply; started.fulfill() }
        }
        StubURLProtocol.enqueue(held, for: "/pages")
        let loading = Task { await bot.loadPages() }
        await fulfillment(of: [started], timeout: 2)

        XCTAssertEqual(bot.pageLoadState, .loading)
        release?()
        await loading.value
        XCTAssertEqual(bot.pageLoadState, .loaded)
        XCTAssertTrue(bot.pages.isEmpty)
    }

    func testCancelledPageListDoesNotReportAChatErrorOrStopTheReply() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let bot = try modelForPageSend()
        bot.beginReply()
        let started = expectation(description: "page request started")
        var held = StubURLProtocol.Stub.json(#"{"pages":[]}"#)
        held.beforeReply = { _ in started.fulfill() }
        StubURLProtocol.enqueue(held, for: "/pages")
        let loading = Task { await bot.loadPages() }
        await fulfillment(of: [started], timeout: 2)

        loading.cancel()
        await loading.value

        XCTAssertNil(bot.errorMessage)
        XCTAssertTrue(bot.isRunning)
        XCTAssertEqual(bot.pageLoadState, .idle)
    }
}
