import SwiftUI

struct PanelsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: PanelsModel?

    var body: some View {
        VStack(alignment: .leading, spacing: Fiesta.Metrics.gutter) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Panels").font(Fiesta.Text.title)
                        .foregroundStyle(Fiesta.Colors.foreground)
                    Text(app.connection.saved?.displayName ?? "")
                        .font(Fiesta.Text.caption)
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                }
                Spacer()
                Button("Settings") { app.showSettings() }
                    .font(Fiesta.Text.body)
            }

            if let message = model?.errorMessage {
                Text(message).font(Fiesta.Text.body)
                    .foregroundStyle(Fiesta.Colors.destructive)
            }

            if model?.isLoading ?? true {
                ProgressView().tint(Fiesta.Colors.brand)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if (model?.panels.isEmpty ?? true) && model?.errorMessage == nil {
                VStack(spacing: 12) {
                    Text("No panels yet").font(Fiesta.Text.heading)
                        .foregroundStyle(Fiesta.Colors.foreground)
                    Text("Create one in the FiestaBoard app under Settings → Hardware → FiestaPanel.")
                        .font(Fiesta.Text.body)
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(model?.panels ?? []) { panel in
                            PanelCard(panel: panel) { app.openPanel(ref: panel.id) }
                        }
                    }
                }
            }
        }
        .padding(Fiesta.Metrics.safeInset)
        .task {
            if model == nil { model = PanelsModel(app: app) }
            await model?.load()
        }
    }
}
