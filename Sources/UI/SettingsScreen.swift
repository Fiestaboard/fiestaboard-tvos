import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: SettingsModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                Text("Settings").font(Fiesta.Text.title)
                    .foregroundStyle(Fiesta.Colors.foreground)

                if let message = model?.errorMessage {
                    Text(message).font(Fiesta.Text.body)
                        .foregroundStyle(Fiesta.Colors.destructive)
                }
                if let warning = model?.warningMessage {
                    Text(warning).font(Fiesta.Text.body)
                        .foregroundStyle(Fiesta.Colors.brand)
                }

                section("Board") {
                    labelled("Name", model?.boardName ?? "")
                    labelled("Address", model?.boardAddress ?? "")
                    HStack(spacing: 20) {
                        FiestaButton("Sign out") { model?.signOut() }
                        FiestaButton("Forget this board") { model?.forget() }
                    }
                }

                section("Open at launch") {
                    Text("Skip the list and go straight to a panel when the app opens.")
                        .font(Fiesta.Text.caption)
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                    ForEach(model?.panels ?? []) { panel in
                        FiestaButton(panel.name + (model?.defaultPanelRef == panel.id ? "  ✓" : "")) {
                            model?.setDefaultPanel(model?.defaultPanelRef == panel.id ? nil : panel.id)
                        }
                    }
                }

                section("Size") {
                    Picker("Sizing", selection: Binding(
                        get: { model?.sizing ?? .fit },
                        set: { model?.setSizing($0) })) {
                        Text("Fit the screen").tag(BoardSizing.fit)
                        Text("True flap size").tag(BoardSizing.trueScale)
                    }
                    .pickerStyle(.segmented)

                    Text(model?.sizing == .trueScale
                         ? "Flaps render at real Vestaboard size. Expect black margins unless the panel was built for this screen."
                         : "The board fills the screen, keeping its shape.")
                        .font(Fiesta.Text.caption)
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                }

                section("Flap animation") {
                    Text("Each changed flap cycles through the drum at 80 ms per step. Choose which panels animate.")
                        .font(Fiesta.Text.caption)
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                    ForEach(model?.panels ?? []) { panel in
                        Toggle(panel.name, isOn: Binding(
                            get: { model?.panels.first(where: { $0.id == panel.id })?.animationsEnabled ?? false },
                            set: { enabled in
                                Task { await model?.setAnimationEnabled(enabled, for: panel) }
                            }))
                    }
                }

                section("Resize a panel for this TV") {
                    Text("Rebuilds the panel's grid on your FiestaBoard for a screen this size.")
                        .font(Fiesta.Text.caption)
                        .foregroundStyle(Fiesta.Colors.mutedForeground)

                    HStack(spacing: 16) {
                        ForEach(SettingsModel.presetDiagonals, id: \.self) { inches in
                            Button("\(Int(inches))\"") { model?.selectPreset(inches) }
                                .font(Fiesta.Text.body)
                        }
                    }

                    TextField("Custom size in inches", text: Binding(
                        get: { model?.customDiagonalText ?? "" },
                        set: { model?.setCustomDiagonal($0) }))
                        .frame(maxWidth: 500)

                    Text("New grid: \(model?.previewGrid ?? "—")")
                        .font(Fiesta.Text.body)
                        .foregroundStyle(Fiesta.Colors.foreground)

                    ForEach(model?.panels ?? []) { panel in
                        FiestaButton("Resize \(panel.name)") {
                            Task { await model?.resize(panel: panel) }
                        }
                    }
                }

                section("True-size calibration") {
                    Text("Adjust real flap size by up to 15% for your TV.")
                        .font(Fiesta.Text.caption)
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                    ForEach(model?.panels ?? []) { panel in
                        HStack(spacing: 20) {
                            Text("\(panel.name): \(Int((model?.calibration(for: panel) ?? 1) * 100))%")
                                .font(Fiesta.Text.body)
                            Button("−1%") {
                                model?.setCalibration((model?.calibration(for: panel) ?? 1) - 0.01,
                                                      for: panel)
                            }
                            Button("+1%") {
                                model?.setCalibration((model?.calibration(for: panel) ?? 1) + 0.01,
                                                      for: panel)
                            }
                            FiestaButton("Save") { Task { await model?.saveCalibration(panel: panel) } }
                        }
                    }
                }

                FiestaButton("Done") { app.showPanels() }
                    .frame(width: 420)
            }
            .padding(Fiesta.Metrics.safeInset)
            .frame(maxWidth: 1200, alignment: .leading)
        }
        .task {
            if model == nil { model = SettingsModel(app: app) }
            await model?.load()
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(Fiesta.Text.heading)
                .foregroundStyle(Fiesta.Colors.foreground)
            content()
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Fiesta.Colors.mutedForeground)
            Spacer()
            Text(value).foregroundStyle(Fiesta.Colors.foreground)
        }
        .font(Fiesta.Text.body)
    }
}
