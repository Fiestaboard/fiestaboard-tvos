import SwiftUI

struct PanelsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: PanelsModel?

    /// Which card holds focus, by panel id.
    @FocusState private var focusedPanel: String?
    /// The scope `prefersDefaultFocus` is answered in.
    @Namespace private var gridScope

    /// Injectable so render tests can drive a loaded model, matching
    /// `ViewerScreen`. A model handed in is taken as already loaded and is
    /// left alone; the `.task` below fetches only for a model this screen
    /// built itself.
    init(model: PanelsModel? = nil) {
        _model = State(initialValue: model)
    }

    /// A card lifts by about a tenth of its size when focused, and the
    /// enclosing `ScrollView` clips to its own bounds. This is the room the
    /// lift needs; without it the selected card's edges are cut off.
    private static let focusInset: CGFloat = 44

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: PanelCard.width, maximum: PanelCard.width),
                  spacing: Fiesta.Metrics.gutter + 16)]
    }

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
        .padding(Fiesta.Metrics.safeInset)
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
        .onDisappear { model?.stopPreviews() }
        .onChange(of: panelIDs) { old, new in
            // Only when the first list lands, and only when no card holds
            // focus already. A TV screen should open with something chosen,
            // and Settings is not it — but once the list is up, focus
            // belongs to whoever is holding the remote, and previews
            // arriving later must never take it back.
            guard old.isEmpty, !new.isEmpty, focusedPanel == nil else { return }
            focusedPanel = defaultFocusID
        }
    }

    private var panelIDs: [String] { model?.panels.map(\.id) ?? [] }

    /// The card to open on: the first one that can actually be opened. A
    /// panel whose board is missing is disabled, so focusing it would
    /// leave the screen with nothing focused at all.
    private var defaultFocusID: String? {
        Self.defaultFocusPanel(in: model?.panels ?? [])
    }

    /// Nil when nothing here can be opened.
    ///
    /// This used to fall back to `panels.first`, which on a list where every
    /// board has been removed names a card that is `.disabled()` — the focus
    /// engine is handed a target it must refuse, and the screen opens with
    /// nothing focused at all. Naming nobody lets tvOS pick the header,
    /// which is at least somewhere the remote can move from.
    static func defaultFocusPanel(in panels: [Panel]) -> String? {
        panels.first(where: { !$0.boardMissing })?.id
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Panels").font(Fiesta.Text.title)
                    .foregroundStyle(Fiesta.Colors.foreground)
                Text(app.connection.saved?.displayName ?? "")
                    .font(Fiesta.Text.caption)
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
            }
            Spacer()
            Button("Settings") { app.showSettings() }
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
            ProgressView().tint(Fiesta.Colors.brand)
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
                ProgressView()
                    .tint(Fiesta.Colors.brand)
                    .opacity(model?.isLoading == true ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .font(Fiesta.Text.body)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading,
                      spacing: Fiesta.Metrics.gutter + 16) {
                ForEach(model?.panels ?? []) { panel in
                    card(for: panel)
                }
            }
            .padding(Self.focusInset)
        }
        // Sideways only: the screen's safe inset already leaves room there,
        // so widening the scroll view into it keeps the cards lined up with
        // the title while giving the lift somewhere to go. Vertically the
        // padding stays, because pulling the scroll view up would let
        // scrolled cards run underneath the header.
        .padding(.horizontal, -Self.focusInset)
        .focusScope(gridScope)
        .focusSection()
    }

    private func card(for panel: Panel) -> some View {
        PanelCard(panel: panel,
                  preview: model?.previewState(for: panel) ?? .loading) {
            app.openPanel(ref: panel.id)
        }
        .focused($focusedPanel, equals: panel.id)
        .prefersDefaultFocus(panel.id == defaultFocusID, in: gridScope)
    }

    /// Never "the FiestaBoard app": `CFBundleDisplayName` is exactly
    /// `FiestaBoard`, so that sent the user to the icon they are already
    /// looking at. Panels are made on the board's own web page — but the
    /// path to them once you are there still has to be named, so it stays.
    /// Hoisted out of the body so the copy rule can be asserted.
    static let emptyStateDetail = "Open your board's web page in a browser on a phone or "
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
