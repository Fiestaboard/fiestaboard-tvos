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
                .frame(height: ScreenRhythm.headingHeight, alignment: .topLeading)
            // 07b A2: the QR at (80, 320), 348 square; the words at x 500.
            HStack(alignment: .top, spacing: 500 - 80 - Self.qrSide) {
                Group {
                    if let url = model?.completeURL { QRCodeView(url: url) }
                    else if model == nil || model?.state == .idle || model?.state == .starting {
                        TacoLoader(size: .large).frame(width: Self.qrSide, height: Self.qrSide)
                            .accessibilityIdentifier("device-code-loading")
                    } else {
                        Image(systemName: "qrcode")
                            .font(.system(size: 120))
                            .foregroundStyle(Fiesta.Colors.mutedForeground)
                            .frame(width: Self.qrSide, height: Self.qrSide)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: Self.qrSide, height: Self.qrSide)
                .figmaNode(Self.a2Slot + ";166:147625")
                VStack(alignment: .leading, spacing: 18) {
                    Text(activationAddress)
                        .font(.title3)
                        .figmaNode(Self.a2Slot + ";166:147627", label: activationAddress)
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
            // 07b A2: the block from y 320, the buttons at y 860 (`166:147655`).
            .padding(.top, 320 - ScreenRhythm.contentTop)
            .frame(height: 860 - Fiesta.Metrics.gutter - ScreenRhythm.contentTop, alignment: .topLeading)
            HStack(spacing: 24) {
                Button(TVCopy.DeviceSignIn.newCode) { model?.start() }.accessibilityIdentifier("device-new-code")
                Button(TVCopy.DeviceSignIn.usePassword) { backToPassword() }
                Button(TVCopy.DeviceSignIn.back) { backToPassword() }
            }
            .figmaNode(Self.a2Slot + ";166:147655")
        }
        // A4a: the system safe area is the 07b title-safe (80/60), and the
        // content hangs from the top as A2 draws it (eyebrow at y 110), not
        // centred in the screen.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    static let qrSide: CGFloat = 348

    /// The 07b A2 frame's Screen slot (`I166:147391;149:182603`).
    private static let a2Slot = "I166:147391;149:182603"
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
