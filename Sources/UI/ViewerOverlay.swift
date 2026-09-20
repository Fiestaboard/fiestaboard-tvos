import SwiftUI

/// Transient chrome over the board.
struct ViewerOverlay: View {
    let panelName: String
    let onPanels: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 20) {
                Text(panelName)
                    .font(Fiesta.Text.heading)
                    .foregroundStyle(Fiesta.Colors.foreground)
                Spacer()
                Button("Panels", action: onPanels).font(Fiesta.Text.body)
                Button("Settings", action: onSettings).font(Fiesta.Text.body)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius))
            .padding(Fiesta.Metrics.safeInset)
            Spacer()
        }
        .transition(.opacity)
    }
}

/// The amber dot from the web viewer: the board is unreachable, the last
/// frame is still true, and the app is still trying.
struct OfflineDot: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Circle()
                    .fill(Fiesta.Colors.offline)
                    .frame(width: 16, height: 16)
                    .padding(Fiesta.Metrics.safeInset)
                    .accessibilityLabel("Disconnected from FiestaBoard. Showing the last message.")
            }
        }
    }
}
