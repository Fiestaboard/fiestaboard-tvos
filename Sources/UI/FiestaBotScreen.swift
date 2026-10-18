import SwiftUI

struct FiestaBotScreen: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: FiestaBotModel
    @State private var path: [Destination] = []
    private enum Destination: Hashable { case panels, pages }

    var body: some View {
        NavigationStack(path: $path) {
            HStack(alignment: .top, spacing: 48) {
                sidebar.frame(width: 390)
                VStack(spacing: 24) {
                    transcript
                    composer
                }
                .focusSection()
            }
            .padding(.horizontal, Fiesta.Metrics.safeInset)
            .padding(.bottom, 36)
            .navigationTitle("FiestaBot")
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .panels: panelChoices
                case .pages: pageChoices
                }
            }
        }
        .background(Fiesta.Colors.background)
        .task { await model.load(preferredRef: app.botPanelRef) }
        .onExitCommand {
            if path.isEmpty { model.stop(); app.dismissFiestaBot() }
            else { path.removeLast() }
        }
    }

    private var sidebar: some View {
        List {
            Section("This conversation") {
                NavigationLink(value: Destination.panels) {
                    VStack(alignment: .leading) {
                        Text("Panel")
                        Text(model.selectedPanel?.name ?? "Choose a panel").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(model.isRunning || model.isShowingPage)
                Button("Show this panel") { model.openSelectedPanel() }
                    .disabled(model.selectedPanel == nil || model.isRunning)
                NavigationLink("Choose a page", value: Destination.pages)
                    .disabled(model.selectedPanel == nil || model.isRunning)
            }
            if model.entries.isEmpty {
                Section("Try asking") {
                    Button("Make a welcome page") { model.submit("Create a welcome page for this panel.") }
                    Button("Show the weather") { model.submit("Create a weather page for this panel using available weather data, then show it here.") }
                    Button("What can I show?") { model.submit("What pages can I show on this panel? Give me a few choices.") }
                }
                .disabled(!model.canSend)
            }
            Section {
                Button("New chat") { model.newConversation() }
                    .disabled(model.isRunning || model.isShowingPage)
                Button("Back to viewer") { model.stop(); app.dismissFiestaBot() }
            }
        }
        .listStyle(.grouped)
    }

    private var transcript: some View {
        List {
            if model.isLoading { ProgressView("Connecting to FiestaBot…") }
            if let message = model.availabilityMessage {
                Section {
                    Text(message).focusable()
                    Button("Check again") { Task { await model.load() } }
                }
            }
            if model.entries.isEmpty {
                Section {
                    Text("Ask FiestaBot to make a page or change what's showing.")
                        .font(.title3).focusable()
                    Text("Requests go to your board and its configured AI provider. This chat stays here until you start a new chat or sign out.")
                        .foregroundStyle(.secondary).font(.caption).focusable()
                }
            }
            ForEach(model.entries) { entry in
                Section(entry.role == "user" ? "You" : "FiestaBot") {
                    if !entry.content.isEmpty { Text(entry.content).focusable() }
                    ForEach(entry.tools) { tool in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(tool.title, systemImage: toolIcon(tool.phase))
                            if !tool.summary.isEmpty { Text(tool.summary).font(.caption).foregroundStyle(.secondary) }
                        }
                        .focusable()
                        if let pageID = tool.pageID {
                            Button("Show page on \(model.selectedPanel?.name ?? "this TV")") {
                                Task { await model.showPage(pageID) }
                            }
                            .disabled(model.isRunning || model.isShowingPage)
                        }
                    }
                }
            }
            if let approval = model.pendingApproval {
                Section("FiestaBot needs your approval") {
                    Text(approval.title).focusable()
                    ForEach((approval.args.objectValue ?? [:]).keys.sorted(), id: \.self) { key in
                        Text("\(key.replacingOccurrences(of: "_", with: " ").capitalized): \(argumentDescription(approval.args[key] ?? .null))")
                            .font(.caption).focusable()
                    }
                    Button("Approve") { model.approve(true) }
                    Button("Decline") { model.approve(false) }
                }.disabled(model.isRunning)
            }
            if let question = model.pendingQuestion {
                Section(question.message) {
                    ForEach(question.options, id: \.self) { option in
                        Button(option) { model.answer(option) }
                    }
                    if question.allowsFreeText { Text("You can also type or dictate your answer below.").font(.caption) }
                    Button("Skip this question") { model.answer(nil, action: "decline") }
                }.disabled(model.isRunning)
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(Fiesta.Colors.destructive).focusable() }
            if model.isRunning {
                HStack { ProgressView(); Text(model.statusText) }
                Button("Stop") { model.stop() }
            }
            if model.canContinue { Button("Continue") { model.continueTurn() }.disabled(model.isRunning) }
        }
        .listStyle(.grouped)
        .accessibilityIdentifier("fiestabot.transcript")
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                TextField(model.pendingQuestion == nil ? "Ask FiestaBot" : "Your answer", text: $model.composer)
                    .accessibilityIdentifier("fiestabot.composer")
                    .onSubmit { model.submit() }
                    .disabled(!model.canSend)
                Button("Send") { model.submit() }
                    .disabled(!model.canSend || model.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("With the keyboard open, hold the Siri button to dictate where available.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var panelChoices: some View {
        List(model.panels) { panel in
            Button {
                model.selectPanel(panel.id)
                path.removeLast()
            } label: {
                HStack {
                    Text(panel.name)
                    Spacer()
                    if model.selectedPanelID == panel.id { Image(systemName: "checkmark") }
                }
            }
        }
        .navigationTitle("Choose a panel")
    }

    private var pageChoices: some View {
        List {
            Section {
                Text("Show a page now on \(model.selectedPanel?.name ?? "this panel"). Its schedule may replace it at the next update.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.pages) { page in
                    Button(page.name) { Task { await model.showPage(page.id) } }
                        .disabled(model.isShowingPage)
                }
                if model.pages.isEmpty { Text("No saved pages available.") }
                if let error = model.errorMessage { Text(error).foregroundStyle(Fiesta.Colors.destructive) }
            }
        }
        .navigationTitle("Show a page")
        .task { await model.loadPages() }
    }

    private func argumentDescription(_ value: JSONValue) -> String {
        if let string = value.stringValue { return string }
        if let array = value.arrayValue { return array.map(argumentDescription).joined(separator: ", ") }
        if let data = try? JSONEncoder().encode(value) { return String(decoding: data, as: UTF8.self) }
        return "—"
    }

    private func toolIcon(_ phase: String) -> String {
        switch phase {
        case "ok", "answered": "checkmark.circle"
        case "error", "blocked": "exclamationmark.circle"
        case "denied", "interrupted": "minus.circle"
        default: "ellipsis.circle"
        }
    }
}
