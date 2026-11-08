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
                    Text(activationAddress)
                        .font(.title3)
                        .accessibilityLabel("Browser address: \(activationAddress)")
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
                    if model?.statusMessage == TVCopy.DeviceSignIn.waiting {
                        DeviceSignInWaitingRow(message: TVCopy.DeviceSignIn.waiting)
                    } else {
                        Text(model?.statusMessage ?? "Creating your code…")
                    }
                    // The corrected scope line (TV-APPS §4 item 4). A3 puts
                    // the device-name sentence in front of it (DD3).
                    // A2 166:147647 / DD3 fallback 249:110266.
                    Text(TVCopy.DeviceSignIn.scopeLine(for: app.deviceName))
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
        // A4a: the system safe area is the 07b title-safe (80/60).
        .onAppear {
            if model == nil {
                model = DeviceSignInModel(connection: app.connection, deviceName: app.deviceName,
                                          onSuccess: { app.finishSignIn(approvedBy: $0) })
                model?.start()
            }
        }
        .onDisappear { model?.cancel() }
        .onExitCommand { backToPassword() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model?.resume() } else { model?.pause() }
        }
    }
    /// DD13: what to type in a browser, as A2 draws it.
    private var activationAddress: String {
        guard let url = model?.manualURL ?? app.connection.saved?.host else { return "" }
        return TVCopy.DeviceSignIn.activationAddress(url)
    }

    private func backToPassword() { model?.cancel(); app.route = .signIn }
}

/// A2 `166:147643` "Waiting": the static 44 pt Taco mark (`166:147644`)
/// beside one line. Static, as A1's "still looking" row: the animated loader
/// drew at ~95 pt here and covered the lines below (#18 review, 4.1).
struct DeviceSignInWaitingRow: View {
    static let markNode = "I166:147391;149:182603;166:147644"

    let message: String

    var body: some View {
        HStack(spacing: 16) {
            TacoMarkView()
                .frame(width: 44, height: 44)
                .figmaNode(Self.markNode)
                .accessibilityHidden(true)
            Text(message)
                .lineLimit(1)
        }
    }
}
