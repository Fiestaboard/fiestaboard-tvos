import SwiftUI

/// One panel, shown as what its board currently says: 07b `tvOS / Panel
/// card` `154:8169`.
///
/// Default (`154:4187`): 800 × 628, the card fill, radius 24; a 450 pt live
/// preview on the board bezel, then the meta block. Focused (`154:6178`): a
/// 6 pt primary outline and a 0/30/60 shadow, with no scale and no
/// parallax: the preview is the frame's "stationary layer". Scaling and
/// tilting a dense board preview makes its pixels shimmer and competes with
/// the scroll motion during remote swipes (A5 decision, DD7 resolved).
struct PanelCard: View {
    let panel: Panel
    let preview: PanelPreviewState
    let action: () -> Void

    // Defaults keep standalone previews useful. The browser passes the width
    // of its actual safe-area column instead of assuming a 1920-point canvas.
    static let width: CGFloat = 800                     // 154:4187
    static let previewHeight: CGFloat = width * 9 / 16  // 450, "Live preview"
    static let detailHeight: CGFloat = 178              // "Meta"
    /// The board inside the preview: 16 pt either side, 4 pt top and bottom
    /// (the 768 × 441.5 board at (16, 4) in the 800 × 450 preview).
    static let boardInset = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
    var cardWidth: CGFloat = Self.width
    var previewImages: PanelPreviewImageCache? = nil
    /// False while the card is far from the viewport: the board picture is
    /// the expensive part of a card, so the browser builds every card but
    /// draws only the pictures near the screen (`PanelsScreen.grid`).
    var showsPreview = true
    /// Shared by the browser's cards, so a summary isn't rebuilt on every
    /// body run (`PanelBoardMessageCache`).
    var boardMessages: PanelBoardMessageCache? = nil

    var body: some View {
        #if DEBUG
        let _ = PanelNavigationProbe.shared.event("card.body")
        #endif
        // Once per body: the subtitle and the label both read it.
        let message = boardMessage
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                previewArea
                details(subtitle: subtitle(message: message))
            }
            .frame(width: cardWidth)
            .background(Fiesta.Colors.surface)
            // 07b's Default has no hairline: the --card plate on the
            // --background ground, the bezel-black preview inside it.
            .clipShape(RoundedRectangle(cornerRadius: PlatformTV.cardRadius))
            .opacity(panel.boardMissing ? 0.45 : 1)
        }
        .buttonStyle(PanelCardButtonStyle())
        .focusEffectDisabled()
        .disabled(panel.boardMissing)
        .accessibilityLabel(accessibilityLabel(message: message))
        .accessibilityHint("Shows this panel full-screen.")
        #if DEBUG
        .modifier(DrawnPreviewMarker(drawn: showsPreview && !panel.boardMissing && preview.isReady))
        #endif
    }

    // MARK: Picture

    private var previewArea: some View {
        ZStack {
            previewContent
        }
        .padding(Self.boardInset)
        .frame(width: cardWidth, height: cardWidth * 9 / 16)
        .background(Color(token: FiestaTokenValues.Board.bezelDark))
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
        } else if !showsPreview {
            // Nothing to draw, and nothing animating, until it's near.
            Color.clear
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

    private func details(subtitle: String) -> some View {
        // 07b "Meta": padding 24 / 32 / 28, gap 6; Caption 1 in primary,
        // Headline, then Body in muted foreground.
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(Fiesta.Text.caption1)
                .foregroundStyle(Fiesta.Colors.brand)
                .lineLimit(1)
            Text(panel.name)
                .font(Fiesta.Text.heading)
                .foregroundStyle(Fiesta.Colors.foreground)
                .lineLimit(1)
            Text(subtitle)
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
                .lineLimit(1)
        }
        .padding(EdgeInsets(top: 24, leading: 32, bottom: 28, trailing: 32))
        .frame(width: cardWidth, height: Self.detailHeight, alignment: .topLeading)
    }

    /// "Split-flap · 29 × 12": the kind, then the grid (07b `154:8166`).
    var eyebrow: String {
        panel.boardMissing ? displayKind : "\(displayKind) · \(panel.gridDescription)"
    }

    private var displayKind: String {
        guard panel.renderStyle == .ledMatrix else { return "Split-flap" }
        return panel.matrixDisplay.appearance?.pixelShape == "round" ? "LED matrix · Round" : "LED matrix · Square"
    }

    var subtitle: String { subtitle(message: boardMessage) }

    var accessibilityLabel: String { accessibilityLabel(message: boardMessage) }

    private func subtitle(message boardMessage: String?) -> String {
        if panel.boardMissing { return panel.gridDescription }
        switch preview {
        case .loading: return "Loading preview…"
        case .unavailable: return "Preview unavailable · Select to open"
        case .ready: return boardMessage ?? "No message yet"
        }
    }

    private func accessibilityLabel(message boardMessage: String?) -> String {
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
        guard let boardMessages else { return Self.boardMessage(panel: panel, ready: ready) }
        return boardMessages.message(for: panel, preview: ready) { Self.boardMessage(panel: panel, ready: ready) }
    }

    private static func boardMessage(panel: Panel, ready: PanelPreview) -> String? {
        let message = ready.message?.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") ?? ""
        if panel.renderStyle == .ledMatrix {
            // Server text already has priority in MatrixRaster.spoken.
            // Avoid rebuilding all pixels just to read that same message.
            if !message.isEmpty { return message }
            #if DEBUG
            PanelNavigationProbe.shared.event("card.raster")
            #endif
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

#if DEBUG
/// See `PanelNavigationProbe.marksDrawnPreviews`.
private struct DrawnPreviewMarker: ViewModifier {
    let drawn: Bool

    // One structure whatever `drawn` is: an `if` here rebuilt the card,
    // and dropped its focus, whenever its row entered or left the window.
    func body(content: Content) -> some View {
        content.accessibilityValue(PanelNavigationProbe.marksDrawnPreviews && drawn
                                   ? PanelNavigationProbe.drawnPreviewValue : "")
    }
}

private extension PanelPreviewState {
    var isReady: Bool { if case .ready = self { true } else { false } }
}
#endif

private struct PanelCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusAppearance(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct FocusAppearance: View {
        let label: ButtonStyleConfiguration.Label
        let isPressed: Bool
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// 07b `tv/focus/outline`.
        static let outline = PlatformTV.focusOutline

        var body: some View {
            label
                // 07b Focused `154:6178`: a 0/30/60 shadow at 60 % black.
                // Always present, only its colour changes, so focusing a
                // card never changes the view's structure.
                .shadow(color: .black.opacity(isFocused ? 0.6 : 0), radius: 30, x: 0, y: 30)
                // The 6 pt primary outline sits OUTSIDE the 800 × 628 body
                // (outer bounds 812 × 640, the Focused symbol's height), so
                // the preview never moves or narrows. Figma draws it inside,
                // narrowing the preview to 788: that would move board pixels.
                .overlay {
                    RoundedRectangle(cornerRadius: PlatformTV.cardRadius + Self.outline)
                        .strokeBorder(Fiesta.Colors.brand, lineWidth: Self.outline)
                        .padding(-Self.outline)
                        .opacity(isFocused ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .opacity(isPressed ? 0.9 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isFocused)
        }
    }
}

/// Lets the browser skip a card whose inputs haven't changed.
///
/// Every card is in the view tree (`PanelsScreen.grid`), and a focus change
/// re-runs the screen's body. SwiftUI can't compare the `action` closure, so
/// without this every card body re-ran on every remote press. The action
/// opens `panel`, so comparing the panel covers it; the caches are compared
/// by identity.
extension PanelCard: @MainActor Equatable {
    static func == (lhs: PanelCard, rhs: PanelCard) -> Bool {
        lhs.panel == rhs.panel && lhs.preview == rhs.preview && lhs.cardWidth == rhs.cardWidth
            && lhs.showsPreview == rhs.showsPreview
            && lhs.previewImages === rhs.previewImages && lhs.boardMessages === rhs.boardMessages
    }
}
