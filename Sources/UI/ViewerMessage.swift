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
    /// Registry probe on the card (A4a geometry test).
    static let probe = "tv:viewer-message"

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
        ViewerGlassContainer { card }
            .onAppear { primaryFocused = true }
    }

    private var card: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

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
        // A4b: the viewer's material (glass on tvOS 26; DD4 interims).
        .viewerSurface(in: cardShape)
        // Lifts the card off a live board behind it.
        .shadow(color: .black.opacity(0.7), radius: 40, y: 16)
        .figmaNode(Self.probe)
        // A4a: the viewer is full-bleed, so title-safe is applied here.
        .padding(EdgeInsets(top: PlatformTV.safeTopBottom, leading: PlatformTV.safeSide, bottom: PlatformTV.safeTopBottom, trailing: PlatformTV.safeSide))
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
