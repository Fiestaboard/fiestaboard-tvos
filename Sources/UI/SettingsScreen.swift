import SwiftUI

/// Select changes category; focus alone never replaces the controls the user
/// is moving toward. Both columns use the platform's own row and focus styles.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: SettingsModel?
    @State private var category: Category = .tv
    @State private var selectedPanelID: String?
    @State private var previewReload = 0
    @State private var panelsReload = 0
    @State private var confirmingForget = false
    @State private var path: [Destination] = []
    @FocusState private var focusedCategory: Category?

    private enum Category: String, CaseIterable, Identifiable {
        case tv = "This Apple TV", appearance = "Panel appearance"
        case connection = "Connection", help = "About & help"
        var id: Self { self }
    }

    private enum Destination: Hashable {
        case panelSelection, launchPanel, flapSizing, matrixSizing, matrixTransition
        case matrixDiagonal, matrixPitch, autoDim, screenDiagonal, displayStyle(String)
        case resize(String), calibration(String), topShelf, privacy, screenProtection
    }

    var body: some View {
        NavigationStack(path: $path) {
            HStack(alignment: .top, spacing: 56) {
                categoryList.frame(width: 400)
                categoryContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // The panel preview sits above the controls. Extend their
                    // focus region so Right from a category reaches the list
                    // even when its first control is lower on the screen.
                    .focusSection()
            }
            .padding(.horizontal, Fiesta.Metrics.safeInset)
            .padding(.bottom, 32)
            .background(Fiesta.Colors.background)
            .navigationTitle("Settings")
            .defaultFocus($focusedCategory, .tv)
            .navigationDestination(for: Destination.self) { detail(for: $0) }
        }
        .onExitCommand {
            if path.isEmpty { app.dismissSettings() }
            else { path.removeLast() }
        }
        .confirmationDialog("Forget this board?", isPresented: $confirmingForget,
                            titleVisibility: .visible) {
            Button("Forget this board", role: .destructive) { model?.forget() }
            Button("Keep it", role: .cancel) { }
        } message: {
            Text("This Apple TV will forget \(model?.boardName ?? "this board") — its address and its saved password — and go back to looking for a board.")
        }
        .task(id: panelsReload) {
            if model == nil { model = SettingsModel(app: app) }
            await model?.load()
            reconcilePanelSelection()
        }
        .onChange(of: model?.panels.map(\.id)) { reconcilePanelSelection() }
    }

    private var categoryList: some View {
        List {
            Section {
                ForEach(Category.allCases) { item in
                    Button { category = item } label: {
                        HStack {
                            Text(item.rawValue)
                            Spacer()
                            if category == item { Image(systemName: "checkmark") }
                        }
                    }
                    .accessibilityLabel(item.rawValue)
                    .accessibilityValue(category == item ? "Selected" : "")
                    .focused($focusedCategory, equals: item)
                }
            }
            Section { Button("Done") { app.dismissSettings() } }
        }
        .listStyle(.grouped)
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch category {
        case .tv:
            controlList {
                Section {
                    choiceLink("Open at launch", value: model?.panels.first { $0.id == defaultPanelBinding.wrappedValue }?.name ?? "Panel list",
                               destination: .launchPanel)
                    .disabled(model?.hasLoaded != true)
                    choiceLink("Split-flap size", value: sizingBinding.wrappedValue == .fit ? "Fit the screen" : "True flap size",
                               destination: .flapSizing)
                } header: { Text("Playback") }
                footer: { Text("Applies only to this Apple TV.") }
                Section {
                    choiceLink("Matrix size", value: matrixSizeOptions.first { $0.0 == matrixSizingBinding.wrappedValue }?.1 ?? "Fill TV",
                               destination: .matrixSizing)
                    .accessibilityIdentifier("settings.matrixSizing")
                    choiceLink("Transition style", value: matrixTransitionStyleBinding.wrappedValue.label,
                               destination: .matrixTransition)
                        .accessibilityIdentifier("settings.matrixTransitionStyle")
                    if model?.matrixPresentation.sizing == .trueSize {
                        choiceLink("TV size", value: "\(Int(matrixDiagonalBinding.wrappedValue)) inches",
                                   destination: .matrixDiagonal)
                        choiceLink("LED spacing", value: "\(Int(matrixPitchBinding.wrappedValue)) mm",
                                   destination: .matrixPitch)
                    }
                } header: { Text("LED matrix") }
                footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(matrixSizingExplanation + " Panels with matrix sizing configured in FiestaBoard use their shared panel settings instead.")
                        Text("Transition style applies only to this Apple TV. Turn on Matrix transitions in Panel appearance to use it.")
                        if reduceMotion { Text("Effects pause while Reduce Motion is on.") }
                    }
                }
                Section {
                    choiceLink("Night dimming", value: autoDimBinding.wrappedValue == .followPanel ? "Follow panel schedule" : "Never dim",
                               destination: .autoDim)
                    Toggle("Slowly shift the board", isOn: driftBinding)
                    NavigationLink("Screen protection & dimming", value: Destination.screenProtection)
                } header: { Text("Screen protection") }
                footer: { Text("Shifting moves the board a few pixels to vary the image.") }
            }
        case .appearance:
            appearanceContent
        case .connection:
            controlList {
                Section("Connected board") {
                    LabeledContent("Name", value: model?.boardName ?? "")
                    LabeledContent("Address", value: model?.boardAddress ?? "")
                }
                Section {
                    Button("Sign out") { model?.signOut() }
                    Button("Forget this board", role: .destructive) { confirmingForget = true }
                } footer: { Text("Nothing on the board itself changes.") }
            }
        case .help:
            controlList {
                Section {
                    LabeledContent("FiestaBoard", value: Self.versionLabel)
                    NavigationLink("Home screen shortcut", value: Destination.topShelf)
                    NavigationLink("Screen protection & dimming", value: Destination.screenProtection)
                    NavigationLink("Privacy", value: Destination.privacy)
                } footer: { Text("Manage content and dimming schedules on your board's web page.") }
            }
        }
    }

    // Explicit destinations avoid an empty native Picker sheet inside the
    // tvOS NavigationStack. Every choice keeps normal List/remote focus.
    private func choiceLink(_ title: String, value: String, destination: Destination) -> some View {
        NavigationLink(value: destination) {
            HStack {
                Text(title)
                Spacer()
                Text(value).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private var matrixSizeOptions: [(MatrixSizing, String)] {
        [(.fillTV, "Fill TV"), (.fitPanel, "Fit panel"), (.trueSize, "True LED size")]
    }

    private func choices<Value: Equatable>(_ title: String, options: [(Value, String)],
                                           selection: Binding<Value>) -> some View {
        controlList {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection.wrappedValue = option.0
                    path.removeLast()
                } label: {
                    HStack {
                        Text(option.1)
                        Spacer()
                        if selection.wrappedValue == option.0 { Image(systemName: "checkmark") }
                    }
                }
                .accessibilityLabel(option.1)
                .accessibilityValue(selection.wrappedValue == option.0 ? "Selected" : "")
            }
        }
        .navigationTitle(title)
    }

    private func controlList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        List {
            messages
            content()
        }
        .listStyle(.grouped)
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var messages: some View {
        if let message = model?.errorMessage {
            Section { Text(message).foregroundStyle(Fiesta.Colors.destructive) }
        }
        if let warning = model?.warningMessage {
            Section { Text(warning).foregroundStyle(Fiesta.Colors.brand) }
        }
        if model == nil || model?.isLoading == true {
            Section { ProgressView("Loading panels…") }
        } else if model?.hasLoaded != true {
            Section { Button("Retry loading panels") { panelsReload += 1 } }
        }
    }

    private var selectedPanel: Panel? { model?.panels.first { $0.id == selectedPanelID } }

    /// Editing selection is independent of this TV's launch preference. Viewer
    /// links may carry either a panel ID or its numeric short reference.
    private func reconcilePanelSelection() {
        guard let panels = model?.panels, !panels.isEmpty else {
            selectedPanelID = nil
            return
        }
        if panels.contains(where: { $0.id == selectedPanelID }) { return }
        let preferred = [app.settingsPanelRef, model?.defaultPanelRef].compactMap { $0 }
        selectedPanelID = preferred.lazy.compactMap { ref in
            panels.first { $0.id == ref || String($0.shortCode) == ref }?.id
        }.first ?? panels.first?.id
    }

    private var appearanceContent: some View {
        VStack(spacing: 12) {
            if let panel = selectedPanel, let model {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsPanelPreview(panel: panel, state: model.previewState(for: panel))
                        .frame(height: 200)
                        .background(.black)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(panel.name) preview")
                        .accessibilityValue(previewDescription(for: panel))
                        .accessibilityIdentifier("settings.panelPreview")
                    HStack {
                        Text(panel.name).font(.headline)
                        Spacer()
                        Text(dimensions(for: panel)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .task(id: "\(panel.id):\(panel.rows ?? 0):\(panel.cols ?? 0):\(previewReload)") {
                    await model.loadPreview(for: panel)
                }
            }
            controlList {
                if let panel = selectedPanel {
                    Section {
                        NavigationLink(value: Destination.panelSelection) {
                            HStack {
                                Text("Panel")
                                Spacer()
                                Text(panel.name).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("settings.panelPicker")
                        .accessibilityLabel("Panel")
                        .accessibilityValue(panel.name)
                        if case .unavailable = model?.previewState(for: panel) {
                            Button("Retry preview") { previewReload += 1 }
                        }
                        if panel.supportsRenderStyle {
                            choiceLink("Display style", value: panel.renderStyle == .splitFlap ? "Split flap" : "LED matrix",
                                       destination: .displayStyle(panel.id))
                            .disabled(model?.isSavingPanel(panel) == true)
                        }
                        Toggle(panel.renderStyle == .ledMatrix ? "Matrix transitions" : "Flap animation",
                               isOn: animationBinding(for: panel))
                            .disabled(reduceMotion || model?.isSavingPanel(panel) == true)
                            .accessibilityIdentifier("settings.animationToggle")
                    } footer: { Text("Applies to every viewer of this panel.") }
                    if reduceMotion {
                        Section {
                            Text(panel.renderStyle == .ledMatrix
                                 ? "Reduce Motion is on. Matrix messages change instantly on this Apple TV."
                                 : "Reduce Motion is on. Flaps change instantly on this Apple TV.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if panel.renderStyle == .splitFlap {
                        Section("Advanced") {
                            NavigationLink("Resize for this TV", value: Destination.resize(panel.id))
                            NavigationLink("True-size calibration", value: Destination.calibration(panel.id))
                        }
                        .disabled(model?.isSavingPanel(panel) == true)
                    }
                } else if model?.hasLoaded == true {
                    Section {
                        Text("No panels yet")
                        Text("Create a panel on your board's web page, then reload.")
                        Button("Reload panels") { panelsReload += 1 }
                    }
                }
            }
        }
    }

    private func previewDescription(for panel: Panel) -> String {
        switch model?.previewState(for: panel) {
        case .ready(let preview): return preview.message ?? "Current board content"
        case .unavailable: return panel.boardMissing ? "Board unavailable" : "Preview unavailable"
        case .loading, .none: return "Loading preview"
        }
    }

    private func dimensions(for panel: Panel) -> String {
        if panel.renderStyle == .ledMatrix {
            return "\(panel.matrixDisplay.width) × \(panel.matrixDisplay.height) pixels"
        }
        guard let cols = panel.cols, let rows = panel.rows else { return "Split flap" }
        return "\(cols) × \(rows) flaps"
    }

    @ViewBuilder
    private func detail(for destination: Destination) -> some View {
        switch destination {
        case .panelSelection:
            controlList {
                ForEach(model?.panels ?? []) { panel in
                    Button {
                        selectedPanelID = panel.id
                        path.removeLast()
                    } label: {
                        HStack {
                            Text(panel.name)
                            Spacer()
                            if panel.id == selectedPanelID { Image(systemName: "checkmark") }
                        }
                    }
                    .accessibilityLabel(panel.name)
                    .accessibilityValue(panel.id == selectedPanelID ? "Selected" : "")
                }
            }
            .navigationTitle("Panel")
        case .launchPanel:
            choices("Open at launch", options: [(String?.none, "Panel list")] + (model?.panels ?? []).map { (Optional($0.id), $0.name) },
                    selection: defaultPanelBinding)
        case .flapSizing:
            choices("Split-flap size", options: [(BoardSizing.fit, "Fit the screen"), (.trueScale, "True flap size")], selection: sizingBinding)
        case .matrixSizing:
            choices("Matrix size", options: matrixSizeOptions, selection: matrixSizingBinding)
        case .matrixTransition:
            choices("Transition style", options: MatrixTransitionStyle.allCases.map { ($0, $0.label) }, selection: matrixTransitionStyleBinding)
        case .matrixDiagonal:
            choices("TV size", options: (SettingsModel.presetDiagonals + [42, 48, 60, 70, 77, 83, 86, 97, 98, 100]).sorted().map { ($0, "\(Int($0)) inches") },
                    selection: matrixDiagonalBinding)
        case .matrixPitch:
            choices("LED spacing", options: [2.0, 3, 4, 5, 6, 8, 10, 12, 16, 20].map { ($0, "\(Int($0)) mm") }, selection: matrixPitchBinding)
        case .autoDim:
            choices("Night dimming", options: [(AutoDimOverride.followPanel, "Follow panel schedule"), (.neverDim, "Never dim")], selection: autoDimBinding)
        case .screenDiagonal:
            choices("Screen size", options: SettingsModel.presetDiagonals.map { ($0, "\(Int($0)) inches") }, selection: diagonalBinding)
        case .displayStyle(let id):
            if let panel = model?.panels.first(where: { $0.id == id }) {
                choices("Display style", options: [(PanelRenderStyle.splitFlap, "Split flap"), (.ledMatrix, "LED matrix")], selection: styleBinding(for: panel))
                    .disabled(model?.isSavingPanel(panel) == true)
            }
        case .resize(let id):
            if let panel = model?.panels.first(where: { $0.id == id && $0.renderStyle == .splitFlap }) {
                controlList { resizeControls(for: panel) }.navigationTitle("Resize \(panel.name)")
            }
        case .calibration(let id):
            if let panel = model?.panels.first(where: { $0.id == id && $0.renderStyle == .splitFlap }) {
                calibrationScreen(for: panel)
            }
        case .topShelf:
            controlList {
                Section("Board shortcut on the Home screen") { Text(Self.topShelfBody) }
            }
            .navigationTitle("Home screen shortcut")
        case .privacy:
            controlList {
                Section { Text(Self.privacyBody) } footer: { Text(Self.privacyFooter) }
            }
            .navigationTitle("Privacy")
        case .screenProtection:
            controlList {
                Section("Night dimming") { Text(model?.autoDimSummary ?? "") }
                Section("Screen protection") { Text(Self.burnInBody) }
            }
            .navigationTitle("Screen protection & dimming")
        }
    }

    private func resizeControls(for panel: Panel) -> some View {
        Section {
            choiceLink("Screen size", value: "\(Int(diagonalBinding.wrappedValue)) inches", destination: .screenDiagonal)
            TextField("Custom size in inches", text: customDiagonalBinding)
            LabeledContent("New grid", value: model?.previewGrid ?? "—")
            Button("Resize \(panel.name)") { Task { await model?.resize(panel: panel) } }
        } header: { Text(panel.name) }
        footer: { Text("Rebuilds this panel's grid. Applies to every viewer of this panel.") }
        .disabled(model?.isSavingPanel(panel) == true)
    }

    /// Measure against the whole TV, not the controls column. Native controls
    /// overlay the board while changes to its true scale remain visible.
    private func calibrationScreen(for panel: Panel) -> some View {
        ZStack(alignment: .trailing) {
            Color.black.ignoresSafeArea()
            if let model {
                SettingsPanelPreview(panel: panel, state: model.previewState(for: panel),
                                     calibrationScale: model.calibration(for: panel))
                    .ignoresSafeArea()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(panel.name) at true flap size")
                    .accessibilityValue(previewDescription(for: panel))
                    .accessibilityIdentifier("settings.calibrationPreview")
                    .task(id: "\(panel.id):\(previewReload)") { await model.loadPreview(for: panel) }
            }
            controlList {
                calibrationControls(for: panel)
                if case .unavailable = model?.previewState(for: panel) {
                    Section { Button("Retry preview") { previewReload += 1 } }
                }
            }
            .frame(width: 590)
            .background(.regularMaterial)
            .padding(.trailing, Fiesta.Metrics.safeInset)
            .padding(.vertical, 32)
        }
        .navigationTitle("Calibrate \(panel.name)")
    }

    private func calibrationControls(for panel: Panel) -> some View {
        let scale = model?.calibration(for: panel) ?? 1
        let percent = Int((scale * 100).rounded())
        let spoken = "\(percent) percent"
        return Section {
            LabeledContent("Flap size", value: "\(percent)%").monospacedDigit()
            Button("Decrease size") { model?.setCalibration(scale - 0.01, for: panel) }
                .accessibilityLabel("Decrease \(panel.name) flap size")
                .accessibilityValue(spoken)
                .disabled(scale <= 0.85)
            Button("Increase size") { model?.setCalibration(scale + 0.01, for: panel) }
                .accessibilityLabel("Increase \(panel.name) flap size")
                .accessibilityValue(spoken)
                .disabled(scale >= 1.15)
            Button("Save calibration") {
                Task {
                    let saved = await model?.saveCalibration(panel: panel) == true
                    if saved, app.route == .settings,
                       path.last == .calibration(panel.id) { path.removeLast() }
                }
            }
            .accessibilityLabel("Save \(panel.name) flap size")
            .accessibilityValue(spoken)
        } header: { Text(panel.name) }
        footer: { Text("Match the visible flaps to their real size, then save. Applies to every viewer of this panel using True flap size.") }
        .disabled(model?.isSavingPanel(panel) == true)
    }

    private static var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private static let burnInBody = """
        FiestaBoard keeps Apple TV awake while a board is showing, so its \
        screen saver won't start. Slowly shifting the board moves it a few \
        pixels over twenty minutes to vary where the image is drawn. \
        Your TV may still reduce brightness to protect its screen; the app \
        cannot turn off those protections.
        """

    private static let topShelfBody = """
        Put FiestaBoard in the top row of the Home screen to see previews of \
        your available panels. Hold Select on the FiestaBoard icon, then move \
        it into the top row. Open the app to refresh the pictures. Select a \
        preview to open that panel.
        """

    /// Pinned by SettingsScreenTests and aligned with the published policy.
    static let privacyBody = """
        Nothing you enter here goes to FiestaBoard's servers, to us, or to \
        any third party: no analytics, no tracking, no account with anybody. \
        What you type goes to the board you chose and to no one else — the \
        board this app found on your network, or the one at the address you \
        typed, wherever that board lives. The board's address and your \
        display preferences are kept in this device's app preferences; your \
        password is kept in this device's Keychain and sent to that board \
        each time this Apple TV signs in. The app collects nothing, shares \
        nothing, and tracks nobody.
        """

    private static let privacyFooter = """
        The full privacy policy is linked from this app's page in the App \
        Store. Apple TV has no web browser, so it can't be opened here.
        """

    // Explicitly typed bindings keep the nested native control builders small.
    private var defaultPanelBinding: Binding<String?> {
        Binding(get: {
            guard let ref = model?.defaultPanelRef else { return nil }
            return model?.panels.first { $0.id == ref || String($0.shortCode) == ref }?.id
        }, set: { model?.setDefaultPanel($0) })
    }

    private var autoDimBinding: Binding<AutoDimOverride> {
        Binding(get: { model?.autoDimOverride ?? .followPanel }, set: { model?.setAutoDimOverride($0) })
    }

    private var sizingBinding: Binding<BoardSizing> {
        Binding(get: { model?.sizing ?? .fit }, set: { model?.setSizing($0) })
    }

    private var matrixSizingBinding: Binding<MatrixSizing> {
        Binding(get: { model?.matrixPresentation.sizing ?? .fillTV }, set: { model?.setMatrixSizing($0) })
    }

    private var matrixTransitionStyleBinding: Binding<MatrixTransitionStyle> {
        Binding(get: { model?.matrixTransitionStyle ?? .characterWipe },
                set: { model?.setMatrixTransitionStyle($0) })
    }

    private var matrixDiagonalBinding: Binding<Double> {
        Binding(get: { model?.matrixPresentation.diagonalInches ?? 55 }, set: { model?.setMatrixDiagonal($0) })
    }

    private var matrixPitchBinding: Binding<Double> {
        Binding(get: { model?.matrixPresentation.pitchMillimeters ?? 6 }, set: { model?.setMatrixPitch($0) })
    }

    private var matrixSizingExplanation: String {
        switch model?.matrixPresentation.sizing ?? .fillTV {
        case .fillTV: return "Extends the LED grid to fill your TV. Keeps the full message and the LEDs' shape. Applies only to this Apple TV."
        case .fitPanel: return "Shows the panel at its original proportions. Space around it stays black. Applies only to this Apple TV."
        case .trueSize: return "Uses your TV's diagonal and the distance between LED centers on a 16:9 screen. Larger panels scale down to keep the full message visible. Applies only to this Apple TV."
        }
    }

    private var diagonalBinding: Binding<Double> {
        Binding(get: { model?.resizeDiagonal ?? 65 }, set: { model?.selectPreset($0) })
    }

    private var customDiagonalBinding: Binding<String> {
        Binding(get: { model?.customDiagonalText ?? "" }, set: { model?.setCustomDiagonal($0) })
    }

    private var driftBinding: Binding<Bool> {
        Binding(get: { model?.driftEnabled ?? false }, set: { model?.setDriftEnabled($0) })
    }

    private func animationBinding(for panel: Panel) -> Binding<Bool> {
        Binding(get: { model?.animationEnabled(for: panel) ?? false },
                set: { enabled in Task { await model?.setAnimationEnabled(enabled, for: panel) } })
    }

    private func styleBinding(for panel: Panel) -> Binding<PanelRenderStyle> {
        Binding(get: { model?.renderStyle(for: panel) ?? panel.renderStyle },
                set: { style in Task { await model?.setRenderStyle(style, for: panel) } })
    }
}
