import SwiftUI

/// Shared configuration, kept as a draft until the board confirms the PATCH.
struct PanelDisplaySettingsScreen: View {
    @State private var draft: PanelSettingsDraft
    @State private var saving = false
    @State private var savedDraft: PanelSettingsDraft?
    let model: SettingsModel

    init(panel: Panel, model: SettingsModel) {
        _draft = State(initialValue: PanelSettingsDraft(panel: panel))
        self.model = model
    }

    var body: some View {
        List {
            Group {
                Section {
                    Text("Changes apply to every viewer of this panel. Save after editing.")
                }
                Section {
                    field("Name", text: $draft.name)
                        .accessibilityIdentifier("panelSettings.name")
                    if draft.original.supportsRenderStyle {
                        choice("Display style", value: draft.renderStyle == .ledMatrix ? "LED matrix" : "Split flap",
                               options: [(PanelRenderStyle.splitFlap, "Split flap"), (.ledMatrix, "LED matrix")],
                               selection: $draft.renderStyle)
                    }
                    Toggle("Animations", isOn: $draft.animationsEnabled)
                } header: { Text("Panel").foregroundStyle(Fiesta.Colors.mutedForeground) }
                Section {
                    choice("Screen size presets", value: "\(draft.diagonalText) inches",
                           options: SettingsModel.presetDiagonals.map { (String($0), "\(Int($0)) inches") },
                           selection: $draft.diagonalText)
                    number("Screen diagonal (3–200 inches)", text: $draft.diagonalText)
                        .accessibilityIdentifier("panelSettings.diagonal")
                    NavigationLink {
                        PanelAspectChoices(width: $draft.aspectWidthText, height: $draft.aspectHeightText)
                    } label: {
                        row("Screen aspect", value: "\(draft.aspectWidthText):\(draft.aspectHeightText)")
                    }
                    number("Aspect width (1–100)", text: $draft.aspectWidthText)
                    number("Aspect height (1–100)", text: $draft.aspectHeightText)
                    number("Calibration (0.85–1.15)", text: $draft.calibrationText)
                        .accessibilityIdentifier("panelSettings.calibration")
                } header: { Text("TV & sizing").foregroundStyle(Fiesta.Colors.mutedForeground) }
                footer: {
                    Text("Screen size and aspect reshape the shared board grid and may require page updates. Aspect sets the grid shape. True LED size uses this TV's actual pixel aspect, diagonal and calibration; the complete grid always fits.")
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                }
                if draft.renderStyle == .ledMatrix {
                    Section {
                        if draft.original.supportsMatrixSettings {
                            choice("Shared matrix size", value: sizingLabel,
                                   options: [(MatrixSizing?.none, "Use each viewer's preference"),
                                             (.some(.fillTV), "Fill TV"), (.some(.fitPanel), "Fit panel"),
                                             (.some(.trueSize), "True LED size")], selection: $draft.matrixSizing)
                                .accessibilityIdentifier("panelSettings.matrixSizing")
                            choice("LED spacing presets", value: "\(draft.pitchText) mm",
                                   options: [2.0, 3, 4, 5, 6, 8, 10, 12, 16, 20].map { (String($0), "\(Int($0)) mm") },
                                   selection: $draft.pitchText)
                            number("LED spacing (1–20 mm)", text: $draft.pitchText)
                        } else {
                            Text("Update FiestaBoard to edit shared matrix sizing and LED spacing. This Apple TV's local matrix preferences remain available.")
                        }
                    } header: { Text("LED matrix").foregroundStyle(Fiesta.Colors.mutedForeground) }
                    footer: { Text("Use each viewer's preference clears shared sizing and restores the local fallback. LED spacing applies to True LED size.").foregroundStyle(Fiesta.Colors.mutedForeground) }
                }
                Section {
                    choice("Web viewer backdrop", value: draft.backdrop.capitalized,
                           options: [("wall", "Wall"), ("dark", "Dark"), ("none", "None")], selection: $draft.backdrop)
                } header: { Text("Backdrop").foregroundStyle(Fiesta.Colors.mutedForeground) }
                footer: { Text("Backdrop decorates the web viewer. Apple TV uses a black full-screen background.").foregroundStyle(Fiesta.Colors.mutedForeground) }
                Section {
                    Toggle("Enable nightly dimming", isOn: $draft.dimEnabled)
                    field("Start (HH:MM)", text: $draft.dimStart)
                        .accessibilityIdentifier("panelSettings.dimStart")
                    field("End (HH:MM)", text: $draft.dimEnd)
                        .accessibilityIdentifier("panelSettings.dimEnd")
                } header: { Text("Shared dim schedule").foregroundStyle(Fiesta.Colors.mutedForeground) }
                footer: { Text("Use the 24-hour clock, such as 22:00 to 07:00. Overnight windows are supported; matching times leave the panel bright. Each viewer uses its own local clock. This Apple TV can override the schedule in Night dimming.").foregroundStyle(Fiesta.Colors.mutedForeground) }
            }
            .disabled(saving)
            Section {
                Button(saving ? "Saving…" : (savedDraft == draft ? "Saved" : "Save changes")) {
                    // Keep the save row focused while the request runs.
                    // Disable only editable fields; guard duplicate presses here.
                    guard !saving, !model.isSavingPanel(draft.original) else { return }
                    saving = true
                    savedDraft = nil
                    Task {
                        defer { saving = false }
                        if let result = await model.saveDisplaySettings(draft) {
                            draft = PanelSettingsDraft(panel: result.panel)
                            savedDraft = draft
                            Announce.say("Display settings saved.")
                        }
                    }
                }
                .accessibilityIdentifier("panelSettings.save")
                if let error = model.errorMessage { Text(error).foregroundStyle(Fiesta.Colors.destructive).focusable() }
                if let warning = model.warningMessage { Text(warning).foregroundStyle(Fiesta.Colors.brand).focusable() }
                if savedDraft == draft { Text("Display settings saved.").accessibilityIdentifier("panelSettings.saved") }
            }
        }
        .listStyle(.grouped)
        .navigationTitle("\(draft.original.name) display")
    }

    private var sizingLabel: String {
        switch draft.matrixSizing {
        case .none: return "Use each viewer's preference"
        case .fillTV: return "Fill TV"
        case .fitPanel: return "Fit panel"
        case .trueSize: return "True LED size"
        }
    }

    private func number(_ title: String, text: Binding<String>) -> some View {
        field(title, text: text, keyboard: .decimalPad)
    }

    /// A placeholder disappears once a field has a value. Keep the meaning
    /// and units visible while someone edits with the TV keyboard.
    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .accessibilityLabel(title)
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }
            .accessibilityElement(children: .combine)
    }

    private func choice<Value: Equatable>(_ title: String, value: String, options: [(Value, String)],
                                         selection: Binding<Value>) -> some View {
        NavigationLink {
            PanelSettingChoices(title: title, options: options, selection: selection)
        } label: { row(title, value: value) }
    }
}

/// Native focusable rows avoid the empty Picker sheet on tvOS.
private struct PanelSettingChoices<Value: Equatable>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        List {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.0
                    dismiss()
                } label: {
                    HStack {
                        Text(option.1)
                        Spacer()
                        if selection == option.0 { Image(systemName: "checkmark") }
                    }
                }
                .accessibilityValue(selection == option.0 ? "Selected" : "")
            }
        }
        .navigationTitle(title)
        .onExitCommand { dismiss() }
    }
}

private struct PanelAspectChoices: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var width: String
    @Binding var height: String
    private let choices = [("16", "9"), ("21", "9"), ("4", "3"), ("9", "16"), ("1", "1")]

    var body: some View {
        List {
            ForEach(choices.indices, id: \.self) { index in
                let aspect = choices[index]
                Button("\(aspect.0):\(aspect.1)") {
                    width = aspect.0
                    height = aspect.1
                    dismiss()
                }
            }
        }
        .navigationTitle("Screen aspect")
        .onExitCommand { dismiss() }
    }
}
