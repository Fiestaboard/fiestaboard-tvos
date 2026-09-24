import SwiftUI

/// The viewer explaining itself.
///
/// These are the three moments the app has to say something instead of
/// showing a board — the panel was deleted, its board is gone, or its grid
/// does not suit this TV. They share one shape so they read as the same
/// kind of event: a card, centred, clearly separated from whatever is
/// behind it, with stock tvOS buttons underneath.
///
/// The card owns its focus rather than leaving it to geometry: while one of
/// these is up the board has given up its full-screen focus target, so the
/// primary action is what the remote should be holding.
struct ViewerMessage: View {
    let title: String
    let detail: String
    let primaryTitle: String
    let primaryAction: () -> Void
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    @FocusState private var primaryFocused: Bool

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title)
                .fontWeight(.semibold)
                .foregroundStyle(Fiesta.Colors.foreground)

            Text(detail)
                .font(.title3)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
                .multilineTextAlignment(.center)

            actions.padding(.top, 16)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 840)
        .padding(.horizontal, 56)
        .padding(.vertical, 48)
        .background(Fiesta.Colors.surface, in: cardShape)
        .overlay(cardShape.strokeBorder(Fiesta.Colors.border, lineWidth: 1))
        // Lifts the card off a live board behind it.
        .shadow(color: .black.opacity(0.7), radius: 40, y: 16)
        .padding(Fiesta.Metrics.safeInset)
        .onAppear { primaryFocused = true }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 20) {
            Button(primaryTitle, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .tint(Fiesta.Colors.brand)
                .focused($primaryFocused)

            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
            }
        }
    }
}
