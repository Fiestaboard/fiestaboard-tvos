import SwiftUI

struct PanelsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: PanelsModel?

    /// Which card holds focus, by panel id.
    @FocusState private var focusedPanel: String?
    /// The scope `prefersDefaultFocus` is answered in.
    @Namespace private var gridScope

    /// Injectable so render tests can drive a loaded model, matching
    /// `ViewerScreen`.
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

            if let message = model?.errorMessage {
                Text(message).font(Fiesta.Text.body)
                    .foregroundStyle(Fiesta.Colors.destructive)
            }

            content
        }
        .padding(Fiesta.Metrics.safeInset)
        .task {
            if model == nil { model = PanelsModel(app: app) }
            await model?.load()
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

    static func defaultFocusPanel(in panels: [Panel]) -> String? {
        panels.first(where: { !$0.boardMissing })?.id ?? panels.first?.id
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

    @ViewBuilder
    private var content: some View {
        if model?.isLoading ?? true {
            ProgressView().tint(Fiesta.Colors.brand)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if (model?.panels.isEmpty ?? true) && model?.errorMessage == nil {
            emptyState
        } else {
            grid
        }
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No panels yet").font(Fiesta.Text.heading)
                .foregroundStyle(Fiesta.Colors.foreground)
            Text("Create one in the FiestaBoard app under Settings → Hardware → FiestaPanel.")
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
