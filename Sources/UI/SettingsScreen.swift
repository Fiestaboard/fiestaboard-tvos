import SwiftUI

/// Select changes category; focus alone never replaces the controls the user
/// is moving toward. Both columns use the platform's own row and focus styles.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: SettingsModel?
    @State private var category: Category
    /// A8e/A8f: a long text page shown in the content column, one focus target.
    @State private var helpDetail: HelpDetail?
    /// S1: which This Apple TV row has focus, to bring the captions under the
    /// last row on screen (they are not focusable, so nothing else scrolls them).
    @FocusState private var thisTVFocus: SettingsLayout.Row?
    private let signage: SignageSettings
    @State private var selectedPanelID: String?
    @State private var previewReload = 0
    @State private var panelsReload = 0
    @State private var confirmingForget = false
    @State private var path: [Destination] = []

    /// `model`: a loaded model, for snapshot tests; the screen builds its own otherwise.
    init(initialCategory: Category = .tv, signage: SignageSettings = .shared, model: SettingsModel? = nil) {
        _category = State(initialValue: initialCategory)
        _model = State(initialValue: model)
        // A loaded model's selection is known now; waiting for the task left
        // the first frame on "No panels yet" (seen on tvOS 26).
        _selectedPanelID = State(initialValue: model?.panels.first?.id)
        self.signage = signage
        preloaded = model != nil
    }

    /// A model handed in already loaded is not reloaded on appear.
    private let preloaded: Bool

    enum HelpDetail: Hashable { case topShelf, screenProtection, privacy, licenses }

    enum Category: String, CaseIterable, Identifiable {
        case tv = "This Apple TV", appearance = "Panel appearance"
        case connection = "Connection", help = "About & help"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .tv: return "appletv"
            case .appearance: return "rectangle.grid.2x2"
            case .connection: return "network"
            case .help: return "questionmark.circle"
            }
        }
    }

    private enum Destination: Hashable {
        case oledCare, panelSelection, launchPanel, flapSizing, matrixSizing, matrixTransition
        case matrixDiagonal, matrixPitch, screenDiagonal, displayStyle(String)
        case displaySettings(String), resize(String), calibration(String)
    }

    /// Registry probe for the content row (A4a geometry test).
    static let contentProbe = "tv:settings-content"

    var body: some View {
        NavigationStack(path: $path) {
            HStack(alignment: .top, spacing: 56) {
                categoryList.frame(width: 440)
                categoryContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // The panel preview sits above the controls. Extend their
                    // focus region so Right from a category reaches the list
                    // even when its first control is lower on the screen.
                    .focusSection()
            }
            // A4a: the system safe area is the 07b title-safe (80/60).
            .figmaNode(Self.contentProbe)
            .padding(.bottom, 32)
            .background(Fiesta.Colors.background)
            .navigationTitle("Settings")
            // Let NavigationStack restore the originating row after a choice
            // closes. A default focus request for the first category can win
            // that restoration race and send focus into the left column.
            .navigationDestination(for: Destination.self) { detail(for: $0) }
        }
        .onExitCommand {
            if helpDetail != nil { helpDetail = nil }
            else if path.isEmpty { app.dismissSettings() }
            else { path.removeLast() }
        }
        .confirmationDialog(TVCopy.Settings.forgetConfirmTitle, isPresented: $confirmingForget,
                            titleVisibility: .visible) {
            Button(TVCopy.Settings.forget, role: .destructive) { model?.forget() }
            Button("Keep it", role: .cancel) { }
        } message: {
            Text("This Apple TV will forget \(model?.boardName ?? "this hub") — its address and its saved sign-in — and go back to looking for a hub.")
        }
        .task(id: panelsReload) {
            if preloaded, panelsReload == 0 {
                reconcilePanelSelection()
                return
            }
            if model == nil {
                model = SettingsModel(app: app, signage: signage)
                if app.settingsPanelRef != nil { category = .appearance }
            }
            await model?.load()
            reconcilePanelSelection()
        }
        .onChange(of: model?.panels.map(\.id)) { reconcilePanelSelection() }
    }

    private var categoryList: some View {
        List {
            Section {
                ForEach(Category.allCases) { item in
                    Button { category = item; helpDetail = nil } label: {
                        HStack {
                            Label(item.rawValue, systemImage: item.symbol)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer()
                            if category == item { Image(systemName: "checkmark") }
                        }
                    }
                    .accessibilityLabel(item.rawValue)
                    .accessibilityValue(category == item ? "Selected" : "")
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
            // DD17 / DD19 (A8 `166:206997`): four sections; TV size and LED
            // spacing only for True LED size, under Matrix size.
            ScrollViewReader { proxy in
                controlList {
                    let sections = SettingsLayout.thisTV(matrixTrueSize: model?.matrixPresentation.sizing == .trueSize)
                    ForEach(sections.indices, id: \.self) { index in
                        let section = sections[index]
                        Section {
                            ForEach(section.rows.indices, id: \.self) { thisTVRow(section.rows[$0]) }
                        } header: { Text(section.title).foregroundStyle(Fiesta.Colors.mutedForeground) }
                    }
                    Section {
                        caption(SettingsCopy.thisTVFooter)
                            .accessibilityIdentifier("settings.thisTVFooter")
                            .id(Self.thisTVEnd)
                    }
                }
                .onChange(of: thisTVFocus) { _, row in
                    guard row == .oledCare else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.thisTVEnd, anchor: .bottom) }
                }
            }
        case .appearance:
            appearanceContent
        case .connection:
            controlList {
                Section {
                    LabeledContent("Name", value: model?.boardName ?? "")
                    LabeledContent("Address", value: model?.boardAddress ?? "")
                } header: { Text(TVCopy.Settings.connectedHeader).foregroundStyle(Fiesta.Colors.mutedForeground) }
                // A8d `269:131778`.
                Section {
                    Button("Sign out") { model?.signOut() }
                    Button(TVCopy.Settings.forget, role: .destructive) { confirmingForget = true }
                } header: { Text("Sign-in").foregroundStyle(Fiesta.Colors.mutedForeground) }
                footer: {
                    Text(SettingsCopy.connectionFooter(deviceCredential: app.connection.usesDeviceCredential,
                                                       tvName: app.deviceName.sent))
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                }
            }
        case .help:
            if let helpDetail {
                helpPage(helpDetail)
            } else {
                // A8e `269:131926`.
                controlList {
                    Section {
                        LabeledContent("FiestaBoard", value: "Version \(Self.versionLabel)")
                        helpRow("Home screen shortcut", .topShelf)
                        helpRow("Screen protection", .screenProtection)
                        helpRow("Privacy", .privacy)
                        helpRow("Licenses", .licenses)
                    } footer: { Text(SettingsCopy.aboutFooter).foregroundStyle(Fiesta.Colors.mutedForeground) }
                    Section {
                        caption(SettingsCopy.screenProtectionCaption)
                    } header: { Text("Screen protection").foregroundStyle(Fiesta.Colors.mutedForeground) }
                }
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
                Text(value).foregroundStyle(Fiesta.Colors.mutedForeground)
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private static let thisTVEnd = "settings.thisTV.end"

    /// 07b draws these as plain captions, not list cells.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Fiesta.Text.caption)
            .foregroundStyle(Fiesta.Colors.mutedForeground)
            .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func thisTVRow(_ row: SettingsLayout.Row) -> some View {
        switch row {
        case .openAtLaunch:
            choiceLink("Open at launch", value: model?.panels.first { $0.id == defaultPanelBinding.wrappedValue }?.name ?? "Panel list",
                       destination: .launchPanel)
            .disabled(model?.hasLoaded != true)
        case .splitFlapSize:
            choiceLink("Split-flap size", value: sizingBinding.wrappedValue == .fit ? "Fit the screen" : "True flap size",
                       destination: .flapSizing)
        case .matrixSize:
            choiceLink("Matrix size", value: matrixSizeOptions.first { $0.0 == matrixSizingBinding.wrappedValue }?.1 ?? "Fill TV",
                       destination: .matrixSizing)
            .accessibilityIdentifier("settings.matrixSizing")
        case .tvSize:
            choiceLink("TV size", value: "\(Int(matrixDiagonalBinding.wrappedValue)) inches", destination: .matrixDiagonal)
        case .ledSpacing:
            choiceLink("LED spacing", value: LEDSpacing.label(matrixPitchBinding.wrappedValue), destination: .matrixPitch)
        case .transitionStyle:
            choiceLink("Transition style", value: matrixTransitionStyleBinding.wrappedValue.label, destination: .matrixTransition)
                .accessibilityIdentifier("settings.matrixTransitionStyle")
        case .oledCare:
            choiceLink("OLED care", value: OLEDCareSummary(app.oledCare, neverDim: model?.autoDimOverride == .neverDim).rowValue,
                       destination: .oledCare)
            .accessibilityIdentifier("settings.oledCare")
            .focused($thisTVFocus, equals: .oledCare)
        case .accessibilityNote:
            caption(SettingsCopy.accessibilityNote)
                .accessibilityIdentifier("settings.accessibilityNote")
        }
    }

    private func helpRow(_ title: String, _ detail: HelpDetail) -> some View {
        Button { helpDetail = detail } label: {
            HStack { Text(title); Spacer(); Image(systemName: "chevron.right").foregroundStyle(Fiesta.Colors.mutedForeground) }
        }
        .accessibilityLabel(title)
    }

    /// DD19: Screen protection, Privacy, Licenses and the shortcut help are
    /// detail pages in the content column, each one scrollable focus target.
    @ViewBuilder
    private func helpPage(_ detail: HelpDetail) -> some View {
        switch detail {
        case .topShelf:
            SettingsDetailPage(title: "Home screen shortcut", body: SettingsCopy.topShelfBody)
        case .screenProtection:
            SettingsDetailPage(title: "Screen protection", body: SettingsCopy.screenProtectionBody)
        case .privacy:
            SettingsDetailPage(title: "Privacy", body: SettingsCopy.privacyBody(tvName: app.deviceName.sent,
                                                                               legacySignIn: !app.connection.usesDeviceCredential),
                               footer: SettingsCopy.privacyFooter)
        case .licenses:
            SettingsDetailPage(title: "Licenses",
                               body: SettingsCopy.licenses().map { "\($0.name)\n\n\($0.text)" }.joined(separator: "\n\n"))
        }
    }

    private var matrixSizeOptions: [(MatrixSizing, String)] {
        [(.fillTV, "Fill TV"), (.fitPanel, "Fit panel"), (.trueSize, "True LED size")]
    }

    private func choices<Value: Equatable>(_ title: String, options: [(Value, String)],
                                           selection: Binding<Value>, footer: String? = nil) -> some View {
        controlList {
            Section {
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
            } footer: {
                if let footer { Text(footer).foregroundStyle(Fiesta.Colors.mutedForeground) }
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
            Section { TacoLoader("Loading panels…") }
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
                HStack(spacing: 28) {
                    SettingsPanelPreview(panel: panel, state: model.previewState(for: panel))
                        .frame(width: 360, height: 196)
                        .padding(14)
                        .background(Fiesta.Colors.surface,
                                    in: RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(panel.name) preview")
                        .accessibilityValue(previewDescription(for: panel))
                        .accessibilityIdentifier("settings.panelPreview")
                    VStack(alignment: .leading, spacing: 12) {
                        Text(panel.name).font(Fiesta.Text.heading).lineLimit(2)
                        Text(dimensions(for: panel)).font(Fiesta.Text.caption).monospacedDigit()
                            .foregroundStyle(Fiesta.Colors.mutedForeground)
                        Text(previewDescription(for: panel))
                            .font(Fiesta.Text.caption)
                            .foregroundStyle(Fiesta.Colors.mutedForeground)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .task(id: "\(panel.id):\(panel.rows ?? 0):\(panel.cols ?? 0):\(previewReload)") {
                    if preloaded, previewReload == 0, case .ready = model.previewState(for: panel) { return }
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
                                Text(panel.name).foregroundStyle(Fiesta.Colors.mutedForeground)
                            }
                        }
                        .accessibilityIdentifier("settings.panelPicker")
                        .accessibilityLabel("Panel")
                        .accessibilityValue(panel.name)
                        if case .unavailable = model?.previewState(for: panel) {
                            Button("Retry preview") { previewReload += 1 }
                        }
                        // DD20: only for legacy password sign-ins.
                        if SettingsLayout.showsAllDisplaySettings(usesDeviceCredential: app.connection.usesDeviceCredential) {
                            NavigationLink("All display settings", value: Destination.displaySettings(panel.id))
                                .accessibilityIdentifier("settings.allDisplaySettings")
                                .disabled(model?.isSavingPanel(panel) == true)
                        }
                        if panel.supportsRenderStyle {
                            choiceLink("Display style", value: panel.renderStyle == .splitFlap ? "Split-flap" : "LED matrix",
                                       destination: .displayStyle(panel.id))
                            .disabled(model?.isSavingPanel(panel) == true)
                        }
                        Toggle(panel.renderStyle == .ledMatrix ? "Matrix transitions" : "Flap animation",
                               isOn: animationBinding(for: panel))
                            .disabled(reduceMotion || model?.isSavingPanel(panel) == true)
                            .accessibilityIdentifier("settings.animationToggle")
                    } footer: {
                        Text(SettingsCopy.appearanceFooter(panelName: panel.name, autoDim: panel.autoDim))
                            .foregroundStyle(Fiesta.Colors.mutedForeground)
                    }
                    if reduceMotion {
                        Section {
                            Text(panel.renderStyle == .ledMatrix
                                 ? "Reduce Motion is on. Matrix messages change instantly on this Apple TV."
                                 : "Reduce Motion is on. Flaps change instantly on this Apple TV.")
                                .foregroundStyle(Fiesta.Colors.mutedForeground)
                        }
                    }
                    if panel.renderStyle == .splitFlap {
                        Section {
                            NavigationLink("Resize for this TV", value: Destination.resize(panel.id))
                            NavigationLink("True-size calibration", value: Destination.calibration(panel.id))
                        } header: { Text("Advanced").foregroundStyle(Fiesta.Colors.mutedForeground) }
                        .disabled(model?.isSavingPanel(panel) == true)
                    }
                } else if model?.hasLoaded == true {
                    Section {
                        Text("No panels yet")
                        Text("Create a panel on your hub's web page, then reload.")
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
        guard let cols = panel.cols, let rows = panel.rows else { return "Split-flap" }
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
            choices("Matrix size", options: matrixSizeOptions, selection: matrixSizingBinding,
                    footer: matrixSizingExplanation + " Shared panel sizing takes priority.")
        case .matrixTransition:
            choices("Transition style", options: MatrixTransitionStyle.allCases.map { ($0, $0.label) }, selection: matrixTransitionStyleBinding)
        case .matrixDiagonal:
            choices("TV size", options: (SettingsModel.presetDiagonals + [42, 48, 60, 70, 77, 83, 86, 97, 98, 100]).sorted().map { ($0, "\(Int($0)) inches") },
                    selection: matrixDiagonalBinding)
        case .matrixPitch:
            // DD21: the shared presets, in their shortest exact form.
            choices("LED spacing", options: LEDSpacing.presets.map { ($0, LEDSpacing.label($0)) }, selection: matrixPitchBinding)
        case .screenDiagonal:
            choices("Screen size", options: SettingsModel.presetDiagonals.map { ($0, "\(Int($0)) inches") }, selection: diagonalBinding)
        case .displayStyle(let id):
            if let panel = model?.panels.first(where: { $0.id == id }) {
                choices("Display style", options: [(PanelRenderStyle.splitFlap, "Split-flap"), (.ledMatrix, "LED matrix")], selection: styleBinding(for: panel))
                    .disabled(model?.isSavingPanel(panel) == true)
            }
        case .displaySettings(let id):
            if let model, let panel = model.panels.first(where: { $0.id == id }) {
                PanelDisplaySettingsScreen(panel: panel, model: model)
            }
        case .resize(let id):
            if let panel = model?.panels.first(where: { $0.id == id && $0.renderStyle == .splitFlap }) {
                controlList { resizeControls(for: panel) }.navigationTitle("Resize \(panel.name)")
            }
        case .calibration(let id):
            if let panel = model?.panels.first(where: { $0.id == id && $0.renderStyle == .splitFlap }) {
                calibrationScreen(for: panel)
            }
        case .oledCare:
            OLEDCareScreen()
        }
    }

    private func resizeControls(for panel: Panel) -> some View {
        Section {
            choiceLink("Screen size", value: "\(Int(diagonalBinding.wrappedValue)) inches", destination: .screenDiagonal)
            TextField("Custom size in inches", text: customDiagonalBinding)
            LabeledContent("New grid", value: model?.previewGrid ?? "—")
            Button("Resize \(panel.name)") { Task { await model?.resize(panel: panel) } }
        } header: { Text(panel.name).foregroundStyle(Fiesta.Colors.mutedForeground) }
        footer: { Text("Rebuilds this panel's grid. Applies to every viewer of this panel.").foregroundStyle(Fiesta.Colors.mutedForeground) }
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
                    .ignoresSafeArea() // full-bleed: true flap size is measured against the whole TV
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
        } header: { Text(panel.name).foregroundStyle(Fiesta.Colors.mutedForeground) }
        footer: { Text("Match the visible flaps to their real size, then save. Applies to every viewer of this panel using True flap size.").foregroundStyle(Fiesta.Colors.mutedForeground) }
        .disabled(model?.isSavingPanel(panel) == true)
    }

    private static var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    // Explicitly typed bindings keep the nested native control builders small.
    private var defaultPanelBinding: Binding<String?> {
        Binding(get: {
            guard let ref = model?.defaultPanelRef else { return nil }
            return model?.panels.first { $0.id == ref || String($0.shortCode) == ref }?.id
        }, set: { model?.setDefaultPanel($0) })
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

    private func animationBinding(for panel: Panel) -> Binding<Bool> {
        Binding(get: { model?.animationEnabled(for: panel) ?? false },
                set: { enabled in Task { await model?.setAnimationEnabled(enabled, for: panel) } })
    }

    private func styleBinding(for panel: Panel) -> Binding<PanelRenderStyle> {
        Binding(get: { model?.renderStyle(for: panel) ?? panel.renderStyle },
                set: { style in Task { await model?.setRenderStyle(style, for: panel) } })
    }
}
