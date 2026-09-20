import SwiftUI

struct ConnectScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: ConnectModel?

    var body: some View {
        VStack(alignment: .leading, spacing: Fiesta.Metrics.gutter) {
            Text("Find your FiestaBoard")
                .font(Fiesta.Text.title)
                .foregroundStyle(Fiesta.Colors.foreground)

            Text("Looking on this network…")
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)

            if let message = app.errorMessage ?? model?.errorMessage {
                Text(message)
                    .font(Fiesta.Text.caption)
                    .foregroundStyle(Fiesta.Colors.destructive)
            }

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(model?.boards ?? []) { board in
                        FiestaButton("\(board.name)  ·  \(board.host.host() ?? "")") {
                            Task { await model?.connect(to: board.host, name: board.name) }
                        }
                    }

                    if model?.boards.isEmpty ?? true {
                        ProgressView().tint(Fiesta.Colors.brand).padding(.vertical, 24)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Or enter the address").font(Fiesta.Text.caption)
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
                TextField("192.168.1.50", text: Binding(
                    get: { model?.manualAddress ?? "" },
                    set: { model?.manualAddress = $0 }))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                FiestaButton("Connect") { Task { await model?.connectManually() } }
            }
        }
        .padding(Fiesta.Metrics.safeInset)
        .onAppear {
            if model == nil { model = ConnectModel(app: app) }
            Task { await model?.startScan() }
        }
        .onDisappear { model?.stopScan() }
    }
}
