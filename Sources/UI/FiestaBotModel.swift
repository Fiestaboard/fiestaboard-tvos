import Foundation
import Observation

struct BotTool: Identifiable {
    let id: String
    let name: String
    let args: JSONValue
    let title: String
    var phase = "running"
    var summary = ""
    var result: JSONValue?

    var pageID: String? {
        guard phase == "ok", ["create_page", "update_page", "get_page"].contains(name) else { return nil }
        return result?["page_id"]?.stringValue ?? result?["id"]?.stringValue
            ?? result?["page"]?["id"]?.stringValue ?? args["page_id"]?.stringValue
    }
}

struct BotEntry: Identifiable {
    let id = UUID()
    let role: String
    var content: String
    var tools: [BotTool] = []
}

struct BotQuestion: Identifiable {
    let id: String
    let message: String
    let options: [String]
    let allowsFreeText: Bool
}

/// One in-memory conversation, bound to one connection and target panel.
/// The server executes tools; this model only presents their reported state.
@MainActor
@Observable
final class FiestaBotModel {
    var entries: [BotEntry] = []
    var currentPage: JSONValue?
    var panels: [Panel] = []
    var pages: [ChatPage] = []
    var selectedPanelID: String?
    var isLoading = false
    var isRunning = false
    var isShowingPage = false
    var canContinue = false
    var pendingApproval: BotTool?
    var pendingQuestion: BotQuestion?
    var errorMessage: String?
    var availabilityMessage: String?
    var statusText = ""
    var composer = ""
    var isAvailable = false
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private let connection: ConnectionStore
    @ObservationIgnored private let client: FiestaClient?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var questionDraft: BotQuestion?
    @ObservationIgnored private var submittedResume: ChatResume?
    @ObservationIgnored private var receivedDone = false
    @ObservationIgnored private var receivedError = false

    init(app: AppModel) {
        self.app = app
        connection = app.connection
        client = app.connection.client
    }

    var selectedPanel: Panel? { panels.first { $0.id == selectedPanelID } }
    var isCurrentConnection: Bool { connection.client === client && !connection.isSignedOut }
    var canSend: Bool {
        isAvailable && selectedPanel != nil && !isRunning && !isShowingPage && pendingApproval == nil
            && pendingQuestion?.allowsFreeText != false
    }

    func load(preferredRef: String? = nil) async {
        guard isCurrentConnection else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await connection.authorized { try await $0.panels() }
            guard isCurrentConnection, !Task.isCancelled else { return }
            panels = loaded.filter { !$0.boardMissing }
            let preferred = panels.first { $0.id == preferredRef || String($0.shortCode) == preferredRef }
            if let preferred, selectedPanelID != preferred.id { selectPanel(preferred.id) }
            if selectedPanel == nil { selectPanel(panels.first?.id) }
            let availability = try await connection.authorized { try await $0.aiAvailability() }
            guard isCurrentConnection, !Task.isCancelled else { return }
            isAvailable = availability.enabled && availability.configured && availability.supportsTV
            availabilityMessage = !availability.supportsTV
                ? "Update FiestaBoard to use FiestaBot on Apple TV. You can still browse panels and pages."
                : (isAvailable ? nil : "Enable FiestaBot and configure an AI provider in your board's web settings to chat here. You can still browse panels and pages.")
        } catch {
            guard !Task.isCancelled else { return }
            availabilityMessage = "FiestaBot isn't available from this board. Check its connection, version, and AI settings."
            report(error)
        }
    }

    func selectPanel(_ id: String?) {
        guard !isRunning, !isShowingPage, selectedPanelID != id else { return }
        newConversation()
        selectedPanelID = id
    }

    func newConversation() {
        stop()
        entries = []
        currentPage = nil
        pendingApproval = nil
        pendingQuestion = nil
        questionDraft = nil
        canContinue = false
        composer = ""
        errorMessage = nil
    }

    func submit(_ text: String? = nil) {
        let text = (text ?? composer).trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !text.isEmpty else { return }
        composer = ""
        if pendingQuestion != nil { answer(text); return }
        entries.append(.init(role: "user", content: text))
        run()
    }

    func approve(_ approved: Bool) {
        guard let pendingApproval, !isRunning else { return }
        run(resume: .init(toolCallId: pendingApproval.id, decision: approved ? "approve" : "deny"))
    }

    func answer(_ text: String?, action: String = "accept") {
        guard let pendingQuestion, !isRunning else { return }
        let answer = ChatAnswer(action: action, content: text.map { ["answer": .string($0)] })
        run(resume: .init(toolCallId: pendingQuestion.id, decision: "answer", answer: answer))
    }

    func continueTurn() { guard canContinue, !isRunning else { return }; run() }

    /// Serialize the server's structured transcript; decisions are resolved by
    /// the resume payload, never pre-recorded as if they already executed.
    func wireMessages(awaiting: String? = nil) -> [ChatWireMessage] {
        entries.flatMap { entry -> [ChatWireMessage] in
            let calls = entry.tools.map { ChatToolCallRecord(id: $0.id, name: $0.name, args: $0.args.objectValue ?? [:]) }
            var wire = [ChatWireMessage(role: entry.role, content: entry.content,
                                        toolCalls: calls.isEmpty ? nil : calls)]
            for tool in entry.tools where tool.id != awaiting {
                guard !["running", "awaiting_approval", "awaiting_input"].contains(tool.phase) else { continue }
                wire.append(.init(role: "tool", toolCallId: tool.id, name: tool.name,
                                  status: tool.phase, result: tool.result ?? .null))
            }
            return wire
        }
    }

    private func run(resume: ChatResume? = nil) {
        guard let panel = selectedPanel, isCurrentConnection, !isRunning else { return }
        let request = ChatRequest(messages: wireMessages(awaiting: resume?.toolCallId), boardId: panel.boardId, resume: resume, currentPage: currentPage)
        let turn = UUID()
        generation = turn
        beginReply(answering: resume)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // Only the initial HTTP response may trigger sign-in recovery.
                // Once a stream starts, retrying could execute a tool twice.
                let stream = try await connection.authorized { try await $0.chat(request) }
                for try await event in stream {
                    guard generation == turn, isCurrentConnection, !Task.isCancelled else { break }
                    receive(event)
                }
                guard generation == turn, isCurrentConnection else { return }
                if !receivedDone {
                    finishInterrupted(message: errorMessage ?? "The reply was interrupted. An action already running may have finished; check the panel before asking again.")
                }
            } catch {
                guard generation == turn, isCurrentConnection else { return }
                let knownRejection: Bool
                if case ChatStreamError.rejected(let status, _) = error { knownRejection = [400, 404, 409, 422].contains(status) }
                else { knownRejection = false }
                finishInterrupted(message: Task.isCancelled ? "Stopped. An action already running may still finish." : error.localizedDescription,
                                  decisionMayHaveRun: !knownRejection)
                if let error = error as? FiestaError, error == .unauthorized { app?.route = .signIn }
            }
            guard generation == turn else { return }
            isRunning = false
            statusText = ""
            task = nil
            if entries.last?.content.isEmpty == true && entries.last?.tools.isEmpty == true { entries.removeLast() }
        }
    }

    func beginReply(answering resume: ChatResume? = nil) {
        submittedResume = resume
        receivedDone = false
        receivedError = false
        canContinue = false
        errorMessage = nil
        isRunning = true
        statusText = "Thinking…"
        entries.append(.init(role: "assistant", content: ""))
    }

    func receive(_ event: ChatEvent) {
        let data = event.data
        // Answer resumes are recorded internally by the server with no
        // tool_result event. Accepted stream activity confirms that decision.
        if let resume = submittedResume, resume.decision == "answer", let answer = resume.answer,
           ["status", "text", "tool_call", "elicitation", "done"].contains(event.name) {
            let value = answer.action == "accept" ? (answer.content?["answer"] ?? .object(answer.content ?? [:]))
                : .string(answer.action == "decline" ? "(declined)" : "(cancelled)")
            updateTool(resume.toolCallId) {
                $0.phase = "answered"
                $0.result = .object(["answer": value])
                $0.summary = value.stringValue ?? "Answered"
            }
            pendingQuestion = nil
            submittedResume = nil
        }
        switch event.name {
        case "text":
            guard let delta = data["delta"]?.stringValue, !entries.isEmpty else { return }
            entries[entries.count - 1].content += delta
        case "status":
            statusText = data["message"]?.stringValue ?? "Working…"
            if data["phase"]?.stringValue == "tool_running", let id = data["tool_call_id"]?.stringValue {
                updateTool(id) { $0.phase = "running" }
                if pendingApproval?.id == id { pendingApproval = nil }
                if pendingQuestion?.id == id { pendingQuestion = nil }
            }
        case "tool_call":
            guard let id = data["id"]?.stringValue, let name = data["name"]?.stringValue, !entries.isEmpty else { return }
            entries[entries.count - 1].tools.append(.init(id: id, name: name,
                args: data["args"] ?? .object([:]), title: data["title"]?.stringValue ?? name.replacingOccurrences(of: "_", with: " ")))
        case "tool_result":
            guard let id = data["id"]?.stringValue else { return }
            updateTool(id) {
                $0.phase = data["status"]?.stringValue ?? "error"
                $0.summary = data["summary"]?.stringValue ?? data["error"]?.stringValue ?? ""
                $0.result = $0.phase == "error" ? .object(["error": data["error"] ?? .string($0.summary)]) : data["result"]
            }
            if let tool = entries.flatMap(\.tools).first(where: { $0.id == id }), let pageID = tool.pageID {
                currentPage = .object(["id": .string(pageID), "name": tool.result?["name"] ?? tool.args["name"] ?? .string("Current page")])
            }
            if pendingApproval?.id == id { pendingApproval = nil }
            if pendingQuestion?.id == id { pendingQuestion = nil }
        case "elicitation":
            guard let id = data["id"]?.stringValue else { return }
            questionDraft = .init(id: id, message: data["message"]?.stringValue ?? "Choose an option",
                options: data["requested_schema"]?["properties"]?["answer"]?["enum"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                allowsFreeText: data["allow_free_text"]?.boolValue ?? true)
        case "warning":
            errorMessage = data["message"]?.stringValue
        case "error":
            receivedError = true
            errorMessage = data["message"]?.stringValue ?? "FiestaBot couldn't complete this request."
        case "done":
            receivedDone = true
            let reason = data["reason"]?.stringValue
            let id = data["pending_tool_call_id"]?.stringValue
            canContinue = reason == "step_limit"
            if reason == "awaiting_approval", let id {
                updateTool(id) { $0.phase = "awaiting_approval" }
                pendingApproval = entries.flatMap(\.tools).first { $0.id == id }
            } else if reason == "awaiting_input", let id, questionDraft?.id == id {
                updateTool(id) { $0.phase = "awaiting_input" }
                pendingQuestion = questionDraft
            } else {
                pendingApproval = nil
                pendingQuestion = nil
            }
        default: break // Advisory tool drafts and future events never trigger actions.
        }
    }

    private func updateTool(_ id: String, _ change: (inout BotTool) -> Void) {
        for entry in entries.indices {
            if let index = entries[entry].tools.firstIndex(where: { $0.id == id }) { change(&entries[entry].tools[index]); return }
        }
    }

    func finishInterrupted(message: String, decisionMayHaveRun: Bool = true) {
        if decisionMayHaveRun, let resume = submittedResume {
            updateTool(resume.toolCallId) {
                if ["running", "awaiting_approval", "awaiting_input"].contains($0.phase) {
                    $0.phase = "interrupted"
                    $0.summary = "Outcome unknown; it may have finished."
                    $0.result = .null
                }
            }
            if pendingApproval?.id == resume.toolCallId { pendingApproval = nil }
            if pendingQuestion?.id == resume.toolCallId { pendingQuestion = nil }
        }
        submittedResume = nil
        for entry in entries.indices {
            for tool in entries[entry].tools.indices where entries[entry].tools[tool].phase == "running" {
                entries[entry].tools[tool].phase = "interrupted"
                entries[entry].tools[tool].summary = "Outcome unknown; it may have finished."
            }
        }
        isRunning = false
        statusText = ""
        errorMessage = message
    }

    func stop() {
        guard isRunning else { return }
        task?.cancel()
        task = nil
        generation = UUID()
        finishInterrupted(message: "Stopped. An action already running may still finish.")
    }

    func loadPages() async {
        do {
            let loaded = try await connection.authorized { try await $0.pages() }
            guard isCurrentConnection, !Task.isCancelled else { return }
            pages = loaded
        } catch { report(error) }
    }

    func showPage(_ id: String) async {
        guard let panel = selectedPanel, !isRunning, !isShowingPage, isCurrentConnection else { return }
        isShowingPage = true
        errorMessage = nil
        defer { isShowingPage = false }
        do {
            let result = try await connection.authorized { try await $0.sendPage(id: id, boardId: panel.boardId) }
            guard isCurrentConnection, !Task.isCancelled else { return }
            guard result.sentToBoard, !result.paused else {
                errorMessage = result.paused
                    ? "The board is paused. Resume playback before showing a page."
                    : "The page wasn't displayed. Check this panel's silence settings and connection."
                return
            }
            // Follow-up requests refer to the page actually shown, including
            // an existing page chosen outside the conversation's tool results.
            let name = pages.first { $0.id == result.pageId }?.name
                ?? (currentPage?["id"]?.stringValue == result.pageId ? currentPage?["name"]?.stringValue : nil)
                ?? "Current page"
            currentPage = .object(["id": .string(result.pageId), "name": .string(name)])
            app?.openPanel(ref: panel.id)
        } catch { report(error) }
    }

    func panelsForTool(_ tool: BotTool) -> [Panel] {
        guard tool.name == "list_panels", tool.phase == "ok" else { return [] }
        let ids = Set((tool.result?["panels"]?.arrayValue ?? []).compactMap { $0["id"]?.stringValue })
        return panels.filter { ids.contains($0.id) && !$0.boardMissing }
    }

    func openPanel(_ panel: Panel) {
        guard isCurrentConnection, !isRunning, !isShowingPage,
              panels.contains(where: { $0.id == panel.id && !$0.boardMissing }) else { return }
        app?.openPanel(ref: panel.id)
    }

    func openSelectedPanel() {
        guard let panel = selectedPanel, isCurrentConnection else { return }
        openPanel(panel)
    }

    private func report(_ error: Error) {
        guard isCurrentConnection else { return }
        if let error = error as? FiestaError {
            if error == .unauthorized { app?.route = .signIn }
            errorMessage = error.userMessage
        } else { errorMessage = error.localizedDescription }
    }
}
