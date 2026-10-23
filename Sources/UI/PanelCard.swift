import SwiftUI

/// One panel, shown as what its board currently says.
///
/// The focus engine handles navigation, while a stationary outline marks the
/// selected card. Scaling and tilting a dense board preview makes its pixels
/// shimmer and competes with the scroll motion during remote swipes.
struct PanelCard: View {
    let panel: Panel
    let preview: PanelPreviewState
    let action: () -> Void

    // Defaults keep standalone previews useful. The browser passes the width
    // of its actual safe-area column instead of assuming a 1920-point canvas.
    static let width: CGFloat = 860
    static let previewHeight: CGFloat = width * 9 / 16
    static let detailHeight: CGFloat = 166
    static let boardInset: CGFloat = 24
    var cardWidth: CGFloat = Self.width
    var previewImages: PanelPreviewImageCache? = nil

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                previewArea
                details
            }
            .frame(width: cardWidth)
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
        .buttonStyle(PanelCardButtonStyle())
        .focusEffectDisabled()
        .disabled(panel.boardMissing)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Shows this panel full-screen.")
    }

    // MARK: Picture

    private var previewArea: some View {
        ZStack {
            previewContent
        }
        .padding(Self.boardInset)
        .frame(width: cardWidth, height: cardWidth * 9 / 16)
        .clipped()
    }

    @ViewBuilder
    private var previewContent: some View {
        if panel.boardMissing {
            // "No board to show" reads as a display fault the app might
            // recover from. Server-side `board_missing` means the virtual
            // board row was DELETED, so say the thing that actually
            // happened — the card, the viewer and `gridDescription` all say
            // it the same way.
            placeholder("Board was removed")
        } else {
            switch preview {
            case .loading:
                TacoLoader()
            case .ready(let ready):
                if let previewImages {
                    PanelPreviewThumbnail(panel: panel, preview: ready, cache: previewImages)
                } else {
                    PanelPreviewBoard(panel: panel, preview: ready)
                }
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
        VStack(alignment: .leading, spacing: 10) {
            Label(displayKind, systemImage: panel.renderStyle == .ledMatrix ? "circle.grid.3x3.fill" : "rectangle.split.3x3.fill")
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.brand)
            Text(panel.name)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Fiesta.Colors.foreground)
                .lineLimit(1)
            Text(subtitle)
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
                .lineLimit(1)
        }
        .padding(.horizontal, 28)
        .frame(width: cardWidth, height: Self.detailHeight, alignment: .leading)
    }

    private var displayKind: String {
        guard panel.renderStyle == .ledMatrix else { return "Split-flap" }
        return panel.matrixDisplay.appearance?.pixelShape == "round" ? "LED matrix · Round" : "LED matrix · Square"
    }

    var subtitle: String {
        if panel.boardMissing { return panel.gridDescription }
        switch preview {
        case .loading: return "Loading preview…"
        case .unavailable: return "Preview unavailable · Select to open"
        case .ready: return boardMessage ?? "No message yet"
        }
    }

    var accessibilityLabel: String {
        var parts: [String] = [panel.name]
        if panel.boardMissing {
            parts.append("Board removed. This panel can't be shown.")
            return parts.joined(separator: ", ")
        }
        parts.append(displayKind)
        parts.append(panel.gridDescription)
        parts.append(panel.screenDescription)
        if let message = boardMessage { parts.append("Board reads: \(message)") }
        return parts.joined(separator: ", ")
    }

    /// A readable summary of the displayed content. Rendered flaps avoid
    /// exposing server colour tokens such as `{63}` in the source message.
    private var boardMessage: String? {
        guard case .ready(let ready) = preview else { return nil }
        let message = ready.message?.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") ?? ""
        if panel.renderStyle == .ledMatrix {
            // Server text already has priority in MatrixRaster.spoken.
            // Avoid rebuilding all pixels just to read that same message.
            if !message.isEmpty { return message }
            let raster = MatrixRaster.make(panel: panel, cells: ready.cells, richCells: ready.richCells, layers: ready.layers)
            guard !message.isEmpty || !raster.text.isEmpty || raster.pixels.contains(where: { $0 != 0 }) else { return nil }
            return raster.spoken(message: ready.message)
        }
        let hasContent = ready.cells.contains { row in
            row.contains { cell in
                switch cell {
                case .blank: return false
                case .character(let value): return !value.isWhitespace
                case .color: return true
                }
            }
        }
        guard !message.isEmpty || hasContent else { return nil }
        return BoardSpeech.spoken(message: hasContent ? nil : ready.message, cells: ready.cells)
    }
}

private struct PanelCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusAppearance(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct FocusAppearance: View {
        let label: ButtonStyleConfiguration.Label
        let isPressed: Bool
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .overlay {
                    RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius)
                        .strokeBorder(Fiesta.Colors.brand, lineWidth: 4)
                        .opacity(isFocused ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .opacity(isPressed ? 0.9 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isFocused)
        }
    }
}
