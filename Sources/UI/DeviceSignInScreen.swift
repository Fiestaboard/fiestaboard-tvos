import SwiftUI

struct DeviceSignInScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: DeviceSignInModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            FiestaScreenHeading(title: "Sign in with a phone or computer",
                                subtitle: "Scan the code, or open the address below in a browser.",
                                context: app.connection.saved?.displayName ?? "FiestaBoard")
            HStack(alignment: .top, spacing: 64) {
                Group {
                    if let url = model?.completeURL { QRCodeView(url: url) }
                    else { ProgressView().frame(width: 390, height: 390) }
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text(model?.manualURL?.absoluteString ?? app.connection.saved?.host.absoluteString ?? "")
                        .font(.title3)
                        .accessibilityLabel("Browser address: \(model?.manualURL?.absoluteString ?? "")")
                    if let challenge = model?.challenge {
                        Text(challenge.userCode).font(.system(size: 60, weight: .bold, design: .monospaced))
                            .accessibilityLabel("Sign-in code: \(challenge.userCode.map(String.init).joined(separator: " "))")
                    }
                    if let expiry = model?.expiresAt {
                        Text("Code expires \(expiry, style: .relative) from now.")
                            .foregroundStyle(Fiesta.Colors.mutedForeground)
                    }
                    Text(model?.statusMessage ?? "Creating your code…")
                    Text("Your browser and TV must both reach this board. If the address won't open, connect your phone or computer to the same network.")
                        .font(.caption).foregroundStyle(Fiesta.Colors.mutedForeground)
                    Text("Allows viewing panels and adjusting their display. FiestaBot needs a separate sign-in with broader permissions and is unavailable for this TV sign-in.")
                        .font(.caption).foregroundStyle(Fiesta.Colors.mutedForeground)
                }
            }
            HStack(spacing: 24) {
                Button("New code") { model?.start() }.accessibilityIdentifier("device-new-code")
                Button("Use username and password") { backToPassword() }
                Button("Back") { backToPassword() }
            }
        }
        .padding(Fiesta.Metrics.safeInset)
        .onAppear {
            if model == nil {
                model = DeviceSignInModel(connection: app.connection, onSuccess: { app.finishSignIn() })
                model?.start()
            }
        }
        .onDisappear { model?.cancel() }
        .onExitCommand { backToPassword() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model?.resume() } else { model?.pause() }
        }
    }
    private func backToPassword() { model?.cancel(); app.route = .signIn }
}
