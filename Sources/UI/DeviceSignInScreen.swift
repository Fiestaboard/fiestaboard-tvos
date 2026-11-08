import SwiftUI

struct DeviceSignInScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: DeviceSignInModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Eyebrow: the hub's name — its Bonjour name until H13 PR 3 (DD8).
            FiestaScreenHeading(title: TVCopy.DeviceSignIn.title,
                                subtitle: model?.completeURL == nil && model?.state != .starting && model != nil
                                    ? TVCopy.DeviceSignIn.retrySubtitle
                                    : TVCopy.DeviceSignIn.subtitle,
                                context: app.connection.saved?.displayName ?? "FiestaBoard")
            HStack(alignment: .top, spacing: 64) {
                Group {
                    if let url = model?.completeURL { QRCodeView(url: url) }
                    else if model == nil || model?.state == .idle || model?.state == .starting {
                        TacoLoader(size: .large).frame(width: 390, height: 390)
                            .accessibilityIdentifier("device-code-loading")
                    } else {
                        Image(systemName: "qrcode")
                            .font(.system(size: 120))
                            .foregroundStyle(Fiesta.Colors.mutedForeground)
                            .frame(width: 390, height: 390)
                            .accessibilityHidden(true)
                    }
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text(model?.manualURL?.absoluteString ?? app.connection.saved?.host.absoluteString ?? "")
                        .font(.title3)
                        .accessibilityLabel("Browser address: \(model?.manualURL?.absoluteString ?? app.connection.saved?.host.absoluteString ?? "")")
                    if let challenge = model?.challenge {
                        Text(challenge.userCode).font(.system(size: 60, weight: .bold, design: .monospaced))
                            .accessibilityLabel("Sign-in code: \(challenge.userCode.map(String.init).joined(separator: " "))")
                    }
                    if let expiry = model?.expiresAt {
                        // A2: "Code expires in 9:57", a minutes:seconds countdown.
                        (Text(TVCopy.DeviceSignIn.expiresPrefix + " ")
                            + Text(timerInterval: Date.now...max(expiry, Date.now), countsDown: true))
                            .foregroundStyle(Fiesta.Colors.mutedForeground)
                    }
                    HStack(spacing: 16) {
                        if model?.statusMessage == TVCopy.DeviceSignIn.waiting {
                            TacoLoader(size: .small).accessibilityHidden(true)
                        }
                        Text(model?.statusMessage ?? "Creating your code…")
                    }
                    // The corrected scope line (TV-APPS §4 item 4). A3 puts
                    // the device-name sentence in front of it (DD3).
                    Text(TVCopy.DeviceSignIn.scope)
                        .font(.caption).foregroundStyle(Fiesta.Colors.mutedForeground)
                    Text(TVCopy.DeviceSignIn.reachability)
                        .font(.caption).foregroundStyle(Fiesta.Colors.mutedForeground)
                }
            }
            HStack(spacing: 24) {
                Button(TVCopy.DeviceSignIn.newCode) { model?.start() }.accessibilityIdentifier("device-new-code")
                Button(TVCopy.DeviceSignIn.usePassword) { backToPassword() }
                Button(TVCopy.DeviceSignIn.back) { backToPassword() }
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
