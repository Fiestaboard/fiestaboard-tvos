import SwiftUI

/// Settings, built the way tvOS builds settings.
///
/// A grouped `List` of `Section`s using the platform's own controls, rather
/// than a stack of brand-filled buttons: tvOS then supplies row heights,
/// focus treatment and spacing, so this screen behaves like every other
/// settings screen on the device. Brand colour is an accent here, not the
/// structure — the viewer is where the brand lives.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: SettingsModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Fiesta.Colors.foreground)
                .padding(.horizontal, Fiesta.Metrics.safeInset)
                .padding(.top, Fiesta.Metrics.safeInset)
                .padding(.bottom, 12)

            List {
                messages
                boardSection
                launchSection
                sizeSection
                animationSection
                dimmingSection
                burnInSection
                resizeSection
                calibrationSection

                Section {
                    Button("Done") { app.dismissSettings() }
                }
            }
            .listStyle(.grouped)
        }
        // tvOS sends Menu to the system when nothing handles it, which quits
        // the app. Settings is never the root, so it always handles it.
        .onExitCommand { app.dismissSettings() }
        .task {
            if model == nil { model = SettingsModel(app: app) }
            await model?.load()
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var messages: some View {
        if let message = model?.errorMessage {
            Section {
                Text(message).foregroundStyle(Fiesta.Colors.destructive)
            }
        }
        if let warning = model?.warningMessage {
            Section {
                Text(warning).foregroundStyle(Fiesta.Colors.brand)
            }
        }
    }

    private var boardSection: some View {
        Section("Board") {
            LabeledContent("Name", value: model?.boardName ?? "")
            LabeledContent("Address", value: model?.boardAddress ?? "")
            Button("Sign out") { model?.signOut() }
            Button("Forget this board", role: .destructive) { model?.forget() }
        }
    }

    /// Single-select, the way tvOS does it: a row per choice with a
    /// checkmark on the current one, not a button whose title changes.
    private var launchSection: some View {
        Section {
            Button {
                model?.setDefaultPanel(nil)
            } label: {
                selectableRow("Show the panel list", isSelected: model?.defaultPanelRef == nil)
            }
            ForEach(model?.panels ?? []) { panel in
                Button {
                    model?.setDefaultPanel(panel.id)
                } label: {
                    selectableRow(panel.name, isSelected: model?.defaultPanelRef == panel.id)
                }
            }
        } header: {
            Text("Open at launch")
        } footer: {
            Text("Skip the list and go straight to a panel when the app opens.")
        }
    }

    private var sizeSection: some View {
        Section {
            Picker("Board size", selection: sizingBinding) {
                Text("Fit the screen").tag(BoardSizing.fit)
                Text("True flap size").tag(BoardSizing.trueScale)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Board size")
        } footer: {
            Text(sizeFooter)
        }
    }

    private var sizeFooter: String {
        model?.sizing == .trueScale
            ? "Flaps render at real Vestaboard size. Expect black margins unless the panel was built for this screen."
            : "The board fills the screen, keeping its shape."
    }

    private var animationSection: some View {
        Section {
            ForEach(model?.panels ?? []) { panel in
                Toggle(panel.name, isOn: animationBinding(for: panel))
            }
        } header: {
            Text("Flap animation")
        } footer: {
            Text("Each changed flap cycles through the drum at 80 ms per step.")
        }
    }

    /// Auto-dim is configured on the server and was, until now, invisible
    /// from the TV: the board went dim at ten and the room had no way to
    /// find out why, let alone stop it.
    ///
    /// The override is this TV's, not the panel's. The window belongs to the
    /// panel and every viewer reads it — the web one included — so switching
    /// it off from here to fix one room would darken, or un-darken, screens
    /// nobody in this room can see.
    private var dimmingSection: some View {
        Section {
            Button {
                model?.setAutoDimOverride(.followPanel)
            } label: {
                selectableRow("Follow the panel's schedule",
                              isSelected: model?.autoDimOverride == .followPanel)
            }
            Button {
                model?.setAutoDimOverride(.neverDim)
            } label: {
                selectableRow("Never dim on this Apple TV",
                              isSelected: model?.autoDimOverride == .neverDim)
            }
        } header: {
            Text("Night dimming")
        } footer: {
            Text(model?.autoDimSummary ?? "")
        }
    }

    /// The honest section. Most of what dims a wall-mounted TV is the TV,
    /// and no app can reach it — so this offers the one lever that does
    /// work, and says plainly what it is for.
    private var burnInSection: some View {
        Section {
            Toggle("Shift the board slowly", isOn: driftBinding)
        } header: {
            Text("Screen burn-in")
        } footer: {
            Text(Self.burnInFooter)
        }
    }

    private static let burnInFooter = """
        While a board is up, the Apple TV is kept awake, so its screen saver \
        won't start. The TV itself is a separate matter: most sets, and every \
        OLED, quietly pull brightness down on a picture that never changes, \
        and no app can switch that off. Turn this on for a board that lives \
        on a wall and it drifts a few pixels over twenty minutes — too slow \
        to notice, enough that the TV stops treating it as a still image. \
        Leave it off for ordinary viewing.
        """

    private var resizeSection: some View {
        Section {
            Picker("Screen size", selection: diagonalBinding) {
                ForEach(SettingsModel.presetDiagonals, id: \.self) { inches in
                    Text("\(Int(inches))\"").tag(inches)
                }
            }
            .pickerStyle(.segmented)

            TextField("Custom size in inches", text: customDiagonalBinding)

            LabeledContent("New grid", value: model?.previewGrid ?? "—")

            ForEach(model?.panels ?? []) { panel in
                Button("Resize \(panel.name)") {
                    Task { await model?.resize(panel: panel) }
                }
            }
        } header: {
            Text("Resize a panel for this TV")
        } footer: {
            Text("Rebuilds the panel's grid on your FiestaBoard for a screen this size.")
        }
    }

    private var calibrationSection: some View {
        Section {
            ForEach(model?.panels ?? []) { panel in
                HStack(spacing: 24) {
                    Text(panel.name)
                    Spacer(minLength: 24)
                    Button("−") {
                        model?.setCalibration((model?.calibration(for: panel) ?? 1) - 0.01, for: panel)
                    }
                    Text("\(Int((model?.calibration(for: panel) ?? 1) * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                    Button("+") {
                        model?.setCalibration((model?.calibration(for: panel) ?? 1) + 0.01, for: panel)
                    }
                    Button("Save") {
                        Task { await model?.saveCalibration(panel: panel) }
                    }
                }
            }
        } header: {
            Text("True-size calibration")
        } footer: {
            Text("Adjust real flap size by up to 15% for your TV.")
        }
    }

    // MARK: Bindings
    //
    // Spelled out with explicit types rather than built inline. Inline
    // `Binding(get:set:)` inside a Picker inside a Section gave the type
    // checker more to infer than it would finish in reasonable time.

    private var sizingBinding: Binding<BoardSizing> {
        Binding(get: { model?.sizing ?? .fit },
                set: { model?.setSizing($0) })
    }

    private var diagonalBinding: Binding<Double> {
        Binding(get: { model?.resizeDiagonal ?? 65 },
                set: { model?.selectPreset($0) })
    }

    private var customDiagonalBinding: Binding<String> {
        Binding(get: { model?.customDiagonalText ?? "" },
                set: { model?.setCustomDiagonal($0) })
    }

    private var driftBinding: Binding<Bool> {
        Binding(get: { model?.driftEnabled ?? false },
                set: { model?.setDriftEnabled($0) })
    }

    private func animationBinding(for panel: Panel) -> Binding<Bool> {
        Binding(get: { model?.animationEnabled(for: panel) ?? false },
                set: { enabled in
                    Task { await model?.setAnimationEnabled(enabled, for: panel) }
                })
    }

    // MARK: Pieces

    private func selectableRow(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 24)
            // Reserve the checkmark's width either way so the titles do not
            // shift as the selection moves between rows.
            Image(systemName: "checkmark")
                .opacity(isSelected ? 1 : 0)
                .foregroundStyle(Fiesta.Colors.brand)
                .accessibilityHidden(!isSelected)
        }
    }
}
