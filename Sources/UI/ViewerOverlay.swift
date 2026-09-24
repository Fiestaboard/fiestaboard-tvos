import SwiftUI

/// Transient chrome over the board.
///
/// The board is the content; this is the only furniture allowed on top of
/// it, so it stays a single bar pinned to the top, sized to its contents,
/// on the system's own `.ultraThinMaterial`. The actions are stock tvOS
/// buttons — the platform supplies their shape, metrics and focus lift, so
/// they read from across a room the same way every other Apple TV button
/// does, and nothing here hand-rolls a focus effect.
struct ViewerOverlay: View {
    let panelName: String
    let onPanels: () -> Void
    let onSettings: () -> Void

    /// Chrome that appears with nothing focused strands the user: the board
    /// itself has given up its focus target while this is on screen, so the
    /// first action has to take focus as the bar arrives.
    @FocusState private var panelsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            bar
            Spacer(minLength: 0)
        }
        .transition(.opacity)
        .onAppear { panelsFocused = true }
    }

    private var bar: some View {
        HStack(spacing: 20) {
            Text(panelName)
                .font(.title2)
                .foregroundStyle(Fiesta.Colors.foreground)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 24)

            Button("Panels", action: onPanels)
                .focused($panelsFocused)
            Button("Settings", action: onSettings)
        }
        .buttonStyle(.bordered)
        // Hug the top: a taller bar hides more of the board than it needs to.
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius))
        .padding(.horizontal, Fiesta.Metrics.safeInset)
        .padding(.top, Fiesta.Metrics.safeInset)
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
