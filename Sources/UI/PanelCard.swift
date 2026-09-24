import SwiftUI

/// One panel, shown as what its board currently says.
///
/// Focus is entirely the platform's: `.buttonStyle(.card)` is the tvOS lift,
/// shadow and parallax. The previous hand-rolled version scaled itself on
/// focus, which grew it past its layout bounds inside the enclosing
/// `ScrollView` — so selecting a panel visibly cut its edges off.
struct PanelCard: View {
    let panel: Panel
    let preview: PanelPreviewState
    let action: () -> Void

    /// Two cards to a row, not three.
    ///
    /// A board is only worth showing if it reads as a board. At three to a
    /// row the flaps came out 19pt tall, which puts the glyphs at under 8pt
    /// and makes `BoardCanvas`'s 1px seam a third the weight of the letter
    /// above it — the board turned into grey stripes. Two to a row is 32pt
    /// flaps, where the seam falls back to a hairline and the message is
    /// legible. The shape is close to a real FiestaPanel grid (30 x 12 lays
    /// out at about 1.85:1) so little of the card is spent letterboxing.
    static let width: CGFloat = 860
    static let previewHeight: CGFloat = 440
    static let detailHeight: CGFloat = 124
    /// The plate left showing around the board.
    ///
    /// Load bearing twice over. It is what mounts the board on the card
    /// instead of bleeding it to the edges — a 30 x 12 grid fits this box
    /// by height, so without it the board takes the card's own top and
    /// bottom edge with it. And measurably it is also what CENTRES the
    /// board: with the preview laid straight into the frame the board came
    /// out flush left, 2pt of plate on one side and 22pt on the other.
    static let boardInset: CGFloat = 14

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                previewArea
                details
            }
            .frame(width: Self.width)
            .background(Fiesta.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius))
            // A hairline, not a focus ring — it is there in every state.
            //
            // The card used to be told apart from the app's ground by
            // being lighter than it. Now that the ground is near-black the
            // plate is only a few values above it, and the board on the
            // card is PURE black, darker than either: the top half of the
            // card read as a hole rather than as a card. `border` is white
            // at 12%, so it draws the edge whatever the surfaces underneath
            // do next.
            .overlay(
                RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius)
                    .strokeBorder(Fiesta.Colors.border, lineWidth: 1))
            .opacity(panel.boardMissing ? 0.45 : 1)
        }
        .buttonStyle(.card)
        .disabled(panel.boardMissing)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Picture

    private var previewArea: some View {
        ZStack {
            previewContent
        }
        // The board is inset rather than bled to the card's edges, so the
        // plate shows as a mount all the way round it. A 30 x 12 grid fits
        // this box by height, which means it would otherwise touch the top
        // and bottom edges exactly and take the card's own edge with it.
        .padding(Self.boardInset)
        .frame(width: Self.width, height: Self.previewHeight)
        .clipped()
    }

    @ViewBuilder
    private var previewContent: some View {
        if panel.boardMissing {
            placeholder("No board to show")
        } else {
            switch preview {
            case .loading:
                ProgressView().tint(Fiesta.Colors.brand)
            case .ready(let ready):
                PanelPreviewBoard(panel: panel, preview: ready)
            case .unavailable:
                placeholder("Preview unavailable")
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(Fiesta.Text.caption)
            .foregroundStyle(Fiesta.Colors.mutedForeground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
    }

    // MARK: Words

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(panel.name)
                .font(Fiesta.Text.body.weight(.semibold))
                .foregroundStyle(Fiesta.Colors.foreground)
                .lineLimit(1)
            Text(subtitle)
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 24)
        .frame(width: Self.width, height: Self.detailHeight, alignment: .leading)
    }

    /// What the board says, when it says anything.
    ///
    /// Even at two cards to a row the flaps are 13pt glyphs — recognisable
    /// as a board, well under the 24pt tvOS treats as the floor for text
    /// read across a room. So the message is also set in type someone can
    /// actually read from the sofa; the grid and screen are the fallback
    /// for a board with nothing on it, and live in Settings anyway.
    var subtitle: String {
        if panel.boardMissing { return panel.gridDescription }
        if let message = boardMessage { return message }
        return "\(panel.gridDescription) · \(panel.screenDescription)"
    }

    var accessibilityLabel: String {
        var parts: [String] = [panel.name]
        if panel.boardMissing {
            parts.append("No board. This panel cannot be shown.")
            return parts.joined(separator: ", ")
        }
        parts.append(panel.gridDescription)
        parts.append(panel.screenDescription)
        if let message = boardMessage { parts.append("Board reads: \(message)") }
        return parts.joined(separator: ", ")
    }

    /// The frame's own message rather than its flaps: VoiceOver reading
    /// 360 characters one row at a time is not a preview, and neither is a
    /// 13pt rendering of them.
    private var boardMessage: String? {
        guard case .ready(let ready) = preview else { return nil }
        guard let message = ready.message else { return nil }
        let flattened = message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flattened.isEmpty ? nil : flattened
    }
}
