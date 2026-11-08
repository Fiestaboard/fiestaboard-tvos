import SwiftUI

struct PanelsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: PanelsModel?
    @State private var restoredInitialFocus = false
    @State private var previewImages: PanelPreviewImageCache
    @State private var boardMessages = PanelBoardMessageCache()
    /// Grid rows whose board pictures are drawn; nil until the scroll view
    /// first reports its geometry (see `previewRows`).
    @State private var previewWindow: Range<Int>?
    /// The focused card a refresh moved into another row, while focus is
    /// owed back to it (see `onChange(of: panelIDs)`).
    @State private var refocusPanel: String?

    /// Which card holds focus, by panel id.
    @FocusState private var focusedPanel: String?
    /// The scope `prefersDefaultFocus` is answered in.
    @Namespace private var gridScope

    /// Injectable so render tests can drive a loaded model, matching
    /// `ViewerScreen`. A model handed in is taken as already loaded and is
    /// left alone; the `.task` below fetches only for a model this screen
    /// built itself.
    ///
    /// `previewImages` is injectable so a render test can see which
    /// pictures were drawn.
    init(model: PanelsModel? = nil, previewImages: PanelPreviewImageCache? = nil) {
        _model = State(initialValue: model)
        _previewImages = State(initialValue: previewImages ?? PanelPreviewImageCache())
    }

    /// Breathing room between cards and the scrolling viewport's edges.
    /// Keep the layout stable as focus moves; the card's outline is inset.
    private static let focusInset: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: Fiesta.Metrics.gutter) {
            // Two focus sections, so the focus engine can cross between
            // them. Without these, moving down off Settings looked for a
            // focusable directly beneath a button in the top right corner,
            // found nothing under it, and left focus where it was — the
            // cards were unreachable from the header.
            header.focusSection()

            content
        }
        // A4a: the system safe area is the 07b title-safe (80/60). The grid
        // ends where A3's card does (y 960, `166:149713`), 60 pt above
        // title-safe bottom. Without it the taller viewport broke the
        // remote's row-by-row walk (PanelsPresentationTests, bisected).
        .padding(.bottom, Self.contentBottom)
        .onAppear {
            #if DEBUG
            PanelNavigationProbe.shared.start()
            #endif
        }
        .onChange(of: panelIDs) { old, new in
            // A card that changes row is rebuilt there (the rows carry the
            // focus sections), so the focus engine hands its focus to the
            // neighbour that took its place. Owe focus back to it. Only when
            // a card had focus: a refresh never takes it from Settings.
            guard let id = focusedPanel, let from = old.firstIndex(of: id), let to = new.firstIndex(of: id),
                  from / 2 != to / 2,
                  model?.panels.first(where: { $0.id == id })?.boardMissing == false else { return }
            refocusPanel = id
        }
        .onChange(of: focusedPanel) { _, id in
            // The engine moves focus off the rebuilt card, through nothing,
            // to its neighbour. At the first card it lands on, give focus
            // back, once.
            guard let owed = refocusPanel, let id else { return }
            refocusPanel = nil
            if id != owed { focusedPanel = owed }
        }
        #if DEBUG
        // In a child, so that reading focus doesn't make this whole screen,
        // and with it every card body, re-run on each remote press.
        .background { FocusChangeProbe(focus: $focusedPanel, ids: panelIDs) }
        #endif
        .task {
            // Only the screen's own model is loaded here. Reloading an
            // injected one overwrote the state a render test had set up
            // with whatever the stub answered next — a seam the view wiped
            // the moment it appeared.
            guard model == nil else { return }
            let fresh = PanelsModel(app: app)
            model = fresh
            await fresh.load()
        }
        .onDisappear {
            #if DEBUG
            PanelNavigationProbe.shared.stop()
            #endif
            model?.stopPreviews()
            previewImages.removeAll()
            boardMessages.removeAll()
            refocusPanel = nil
        }
    }

    private var panelIDs: [String] { model?.panels.map(\.id) ?? [] }

    /// The 07b A3 frame's Screen slot (`I166:147702;149:182603`).
    private static let a3Slot = "I166:147702;149:182603"

    /// Restore the panel just watched, falling back to the first available
    /// panel if it was removed. Never restore focus to a disabled card.
    private var defaultFocusID: String? {
        Self.defaultFocusPanel(in: model?.panels ?? [], preferredRef: app.lastViewedPanelRef)
    }

    /// Nil when nothing here can be opened.
    ///
    /// This used to fall back to `panels.first`, which on a list where every
    /// board has been removed names a card that is `.disabled()` — the focus
    /// engine is handed a target it must refuse, and the screen opens with
    /// nothing focused at all. Naming nobody lets tvOS pick the header,
    /// which is at least somewhere the remote can move from.
    static func defaultFocusPanel(in panels: [Panel], preferredRef: String? = nil) -> String? {
        let available = panels.filter { !$0.boardMissing }
        return available.first { $0.id == preferredRef || String($0.shortCode) == preferredRef }?.id
            ?? available.first?.id
    }

    private var header: some View {
        HStack {
            // Eyebrow: the hub's name — its Bonjour name until H13 PR 3 (DD8).
            FiestaScreenHeading(title: TVCopy.Panels.title,
                                subtitle: app.oledCare.invitationDismissed
                                    ? TVCopy.Panels.subtitle
                                    : TVCopy.Panels.subtitleWithOLEDInvitation,
                                context: app.connection.saved?.displayName ?? "FiestaBoard")
            Spacer(minLength: 32)
            Button { app.showSettings() } label: {
                Label(TVCopy.Panels.settings, systemImage: "gearshape")
            }
            .font(Fiesta.Text.body)

        }
    }

    /// Still loading, loaded and empty, and failed are three different
    /// things and each gets its own screen.
    ///
    /// Failed used to have none: it fell through to the grid, so a board
    /// that could not be reached showed as one line of red text above an
    /// empty rectangle — nothing that said what had happened, and no control
    /// anywhere on the screen to try it again.
    @ViewBuilder
    private var content: some View {
        switch Self.contentState(hasPanels: !(model?.panels.isEmpty ?? true),
                                 isLoading: model?.isLoading ?? true,
                                 errorMessage: model?.errorMessage) {
        case .loading:
            loadingState
        case .grid(let banner):
            loadedGrid(banner: banner)
        case .failure(let message):
            failureState(message)
        case .empty:
            emptyState
        }
    }

    /// Which of those four screens is up.
    enum ContentState: Equatable {
        case loading
        /// The cards, carrying the message from a failed *refresh*.
        case grid(banner: String?)
        case failure(String)
        case empty
    }

    /// Cards first.
    ///
    /// `isLoading` used to be asked first, so a refresh of a list that was
    /// already up threw the cards away for a full-screen spinner — on the
    /// most-travelled path in the app, the walk back from the viewer.
    /// Panels already on screen are still true; the spinner is for having
    /// nothing to show yet.
    ///
    /// Failure outranks loading for the same reason read backwards.
    /// `PanelsModel.load` leaves the last attempt's message up while the
    /// next one is in flight, so a retry keeps the screen it was pressed
    /// on — and with it the focused button — instead of dropping to the
    /// spinner and taking focus back to the header.
    static func contentState(hasPanels: Bool, isLoading: Bool,
                             errorMessage: String?) -> ContentState {
        if hasPanels { return .grid(banner: errorMessage) }
        if let errorMessage { return .failure(errorMessage) }
        return isLoading ? .loading : .empty
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            TacoLoader(size: .large)
                .accessibilityHidden(true)
            Text("Asking your FiestaBoard for its panels…")
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The grid, with a note above it when a *refresh* failed.
    ///
    /// Cards already on screen are still true, they are just no longer
    /// fresh — throwing them away to show an error would be a worse screen
    /// than the one that is up.
    private func loadedGrid(banner: String?) -> some View {
        VStack(alignment: .leading, spacing: Fiesta.Metrics.gutter) {
            if let banner {
                HStack(spacing: 24) {
                    Text(banner).font(Fiesta.Text.body)
                        .foregroundStyle(Fiesta.Colors.destructive)
                    retryButton
                }
                .focusSection()
            }
            grid
        }
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Couldn't load your panels").font(Fiesta.Text.heading)
                .foregroundStyle(Fiesta.Colors.foreground)
            Text(message).font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.destructive)
                .multilineTextAlignment(.center)
            retryButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Same reason the header has one: with the grid gone this button is
        // the only focusable below the title, and the focus engine looks for
        // something directly beneath wherever it currently is. Without a
        // section of its own, moving down off "Settings" — in the top right
        // corner — finds nothing under it and the remote never reaches the
        // one control on the screen.
        .focusSection()
    }

    /// Stays mounted, focusable and the same size for the whole of the
    /// reload it starts; the spinner goes inside it.
    ///
    /// Swapping the button for a progress view took the focused view out of
    /// the tree mid-press, so focus fell back to the header and every retry
    /// cost a trip back down the screen. `.disabled` while it runs does the
    /// same thing — tvOS cannot leave focus on a disabled view — so the
    /// second-press guard is in the action, and the spinner holds its space
    /// when it is not spinning so the button never moves under the thumb.
    private var retryButton: some View {
        Button {
            guard model?.isLoading != true else { return }
            Task { await model?.load() }
        } label: {
            HStack(spacing: 12) {
                Text("Try again")
                TacoLoader(size: .small, isAnimating: model?.isLoading == true)
                    .opacity(model?.isLoading == true ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .font(Fiesta.Text.body)
    }

    /// The column gap and the row gap.
    static let gridSpacing: CGFloat = 48
    /// Rows either side of the viewport whose pictures are drawn ahead of
    /// being scrolled to.
    static let previewLookahead = 1

    /// Every card is built up front; only the board pictures are lazy.
    ///
    /// This was a `LazyVGrid`, whose rows below the viewport aren't views
    /// until they scroll in. Down at that boundary, under CPU load, found no
    /// card beneath: focus fell to nothing (in the native move, or in the
    /// app's fallback racing it), and tvOS then ignored focus requests for
    /// seconds (`program/status/tv-panels-flake.md`). A card
    /// without its picture costs a few text views, so all of them are here
    /// for the focus engine to find. The picture is what is expensive, so
    /// only rows within `previewLookahead` of the viewport draw one, which
    /// also keeps the working set inside `PanelPreviewImageCache`'s limit.
    private var grid: some View {
        GeometryReader { proxy in
            let spacing = Self.gridSpacing
            // Two columns, each at most A3's 800 pt card (`166:149713`,
            // 800 × 640). A4a widened the content to the 1760 pt title-safe;
            // uncapped, cards grew to 856 pt and their taller rows broke the
            // remote's row-by-row walk (PanelsPresentationTests). A5 owns the
            // grid's final geometry.
            let cardWidth = max(1, min(Self.maxCardWidth, (proxy.size.width - spacing) / 2))
            let panels = model?.panels ?? []
            let rowCount = (panels.count + 1) / 2
            let rowHeight = Self.cardHeight(width: cardWidth)
            let window = previewWindow ?? Self.previewRows(visibleMinY: 0, visibleHeight: proxy.size.height,
                                                           rowHeight: rowHeight, rowCount: rowCount)
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: spacing) {
                        ForEach(0..<rowCount, id: \.self) { row in
                            PanelGridRow(spacing: spacing) {
                                ForEach(panels[(row * 2)..<min(row * 2 + 2, panels.count)]) { panel in
                                    card(for: panel, width: cardWidth, showsPreview: window.contains(row))
                                        .id(panel.id)
                                }
                            }
                            // Down from the right column into an odd last
                            // row, or past a column of removed boards, has
                            // nothing directly beneath it. A row-wide section
                            // is, so the focus engine enters the row and
                            // takes its nearest card.
                            .focusSection()
                        }
                    }
                    .padding(Self.focusInset)
                }
                .onScrollGeometryChange(for: Range<Int>.self) { geometry in
                    Self.previewRows(visibleMinY: geometry.visibleRect.minY,
                                     visibleHeight: geometry.visibleRect.height,
                                     rowHeight: rowHeight, rowCount: rowCount)
                } action: { _, window in
                    previewWindow = window
                }
                // Expand the viewport, then inset its content without moving
                // the columns out of alignment with the heading.
                .padding(.horizontal, -Self.focusInset)
                .focusScope(gridScope)
                .focusSection()
                .task(id: panelIDs) {
                    guard !restoredInitialFocus, !panelIDs.isEmpty else { return }
                    restoredInitialFocus = true
                    guard focusedPanel == nil, let id = defaultFocusID else { return }
                    scroll.scrollTo(id, anchor: .center)
                    focusedPanel = id
                }
            }
        }
    }

    /// A card's height at `width`: its 16:9 picture and the words under it.
    ///
    /// `previewRows` derives the row pitch from this, so it must follow
    /// `PanelCard`'s real height. When A5 changes the card (07b's 640 pt
    /// height, the `.card` lift), change this with it, or the preview window
    /// drifts by a row. `testTheCardIsAsTallAsCardHeightSays` pins the two.
    static func cardHeight(width: CGFloat) -> CGFloat {
        width * 9 / 16 + PanelCard.detailHeight
    }

    /// The rows whose pictures are drawn when the scroll view shows content
    /// from `visibleMinY` for `visibleHeight` points: every row that band
    /// touches, and `lookahead` more on each side.
    static func previewRows(visibleMinY: CGFloat, visibleHeight: CGFloat, rowHeight: CGFloat,
                            rowCount: Int, lookahead: Int = previewLookahead) -> Range<Int> {
        guard rowCount > 0, rowHeight > 0, visibleHeight > 0 else { return 0..<0 }
        let pitch = rowHeight + gridSpacing
        let first = Int(((visibleMinY - focusInset) / pitch).rounded(.down))
        let last = Int(((visibleMinY + visibleHeight - focusInset) / pitch).rounded(.down))
        let lower = min(max(0, first - lookahead), rowCount)
        let upper = max(lower, min(rowCount, last + 1 + lookahead))
        return lower..<upper
    }

    private func card(for panel: Panel, width: CGFloat, showsPreview: Bool) -> some View {
        PanelCard(panel: panel,
                  preview: model?.previewState(for: panel) ?? .loading,
                  action: { app.openPanel(ref: panel.id) }, cardWidth: width,
                  previewImages: previewImages, showsPreview: showsPreview,
                  boardMessages: boardMessages)
        .equatable()
        .figmaNode(Self.a3Slot + ";166:149713", enabled: panel.id == panelIDs.first)
        .focused($focusedPanel, equals: panel.id)
        .prefersDefaultFocus(panel.id == defaultFocusID, in: gridScope)
    }

    /// Never "the FiestaBoard app": `CFBundleDisplayName` is exactly
    /// `FiestaBoard`, so that sent the user to the icon they are already
    /// looking at. Panels are made on the board's own web page — but the
    /// path to them once you are there still has to be named, so it stays.
    /// Hoisted out of the body so the copy rule can be asserted.
    /// A3 `tvOS / Panel card` instance width.
    static let maxCardWidth: CGFloat = 800
    /// A3: content ends at y 960, 60 pt above the title-safe bottom.
    static let contentBottom: CGFloat = 1080 - 60 - 960

    static let emptyStateDetail = "Open your hub's web page in a browser on a phone or "
        + "computer and create one under Settings → Hardware → FiestaPanel."

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No panels yet").font(Fiesta.Text.heading)
                .foregroundStyle(Fiesta.Colors.foreground)
            Text(Self.emptyStateDetail)
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One row of the panel grid: two columns, built eagerly.
///
/// It places cards where the `LazyVGrid` with two flexible columns did:
/// each column is half the width less the gap, a card sits at its cell's
/// leading edge, centred vertically in a row as tall as its tallest card,
/// and a lone last card sits in the left column.
struct PanelGridRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: height(of: subviews, column: columnWidth(width)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = columnWidth(bounds.width)
        let cell = ProposedViewSize(width: column, height: nil)
        for (side, card) in subviews.prefix(2).enumerated() {
            let x = bounds.minX + CGFloat(side) * (column + spacing)
            card.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: cell)
        }
    }

    private func columnWidth(_ width: CGFloat) -> CGFloat {
        max(0, (width - spacing) / 2)
    }

    private func height(of subviews: Subviews, column: CGFloat) -> CGFloat {
        subviews.prefix(2).map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
    }
}

#if DEBUG
/// Records each card focus change for `PanelNavigationProbe`.
private struct FocusChangeProbe: View {
    let focus: FocusState<String?>.Binding
    let ids: [String]

    var body: some View {
        Color.clear
            .onChange(of: focus.wrappedValue) { _, id in
                PanelNavigationProbe.shared.event("focus.changed", index: ids.firstIndex(of: id ?? "") ?? -1)
            }
    }
}
#endif
