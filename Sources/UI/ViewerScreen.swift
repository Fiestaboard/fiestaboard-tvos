import SwiftUI

struct ViewerScreen: View {
    let ref: String
    @Environment(AppModel.self) private var app
    @State private var model: ViewerModel?

    /// Injectable so render tests can drive a fixed snapshot.
    init(ref: String, model: ViewerModel? = nil) {
        self.ref = ref
        _model = State(initialValue: model)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Switch off OLED pixels outside the lit flaps.
                Color.black.ignoresSafeArea()

                board(in: proxy.size)
                wakeTarget

                if model?.snapshot.connection == .stale { OfflineDot() }
                if model?.resizeOfferVisible == true { resizeOffer }
                if model?.overlayVisible == true { overlay }
            }
            // Burn-in drift, off unless this TV opted in. A couple of points
            // a minute: the panel stops seeing a still image, the room
            // cannot see it move.
            .offset(x: model?.snapshot.drift.x ?? 0, y: model?.snapshot.drift.y ?? 0)
            // Auto-dim uses the TV's own clock, matching the web viewer.
            .opacity(model?.snapshot.dimmed == true ? 0.35 : 1.0)
            .animation(.easeInOut(duration: 1.0), value: model?.snapshot.dimmed)
            .onChange(of: [model?.snapshot.rows ?? 0, model?.snapshot.cols ?? 0]) { _, _ in
                model?.considerResizeOffer(for: proxy.size)
            }
            .onChange(of: proxy.size) { _, _ in model?.considerResizeOffer(for: proxy.size) }
        }
        .ignoresSafeArea()
        .onAppear {
            if model == nil { model = ViewerModel(app: app, ref: ref) }
            model?.start()
            // Keeping the TV awake is AppModel's job, not this view's: it
            // follows the route, so it cannot be lost to the ordering
            // between one screen's onDisappear and the next one's onAppear.
        }
        .onDisappear { model?.stop() }
        .onMoveCommand { _ in model?.showOverlay() }
        .onPlayPauseCommand { model?.showOverlay() }
        .onExitCommand { model?.stop(); app.showPanels() }
    }

    // MARK: Layers
    //
    // Each branch of the stack is its own property. Inlined in `body` they
    // gave the type checker one expression with several conditionals and a
    // throwing call inside it, which is the shape docs/tvos-design.md warns
    // about.

    @ViewBuilder
    private func board(in size: CGSize) -> some View {
        if model?.snapshot.deleted == true {
            deletedState
        } else if model?.boardMissing == true {
            missingBoardState
        } else if let layout = try? model?.layout(for: size) {
            canvas(for: layout)
        } else {
            ProgressView().tint(Fiesta.Colors.brand)
        }
    }

    private func canvas(for layout: BoardLayout) -> some View {
        BoardCanvas(layout: layout,
                    background: model?.snapshot.panel?.backgroundColor ?? .black,
                    animated: model?.snapshot.panel?.animationsEnabled ?? false,
                    code62: model?.snapshot.panel?.effectiveCode62 ?? .degree)
            .frame(width: layout.width, height: layout.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The canvas needs a remote target, but a full-screen tvOS Button
    /// paints its focus material over the entire board.
    ///
    /// It gives that target up the moment anything else is on screen. The
    /// focus engine picks by geometry, and a focusable covering the whole
    /// display beats every button in it — leaving the overlay's Panels and
    /// Settings unreachable, because moving in any direction just landed
    /// back here.
    private var wakeTarget: some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable(boardIsTheOnlyTarget, interactions: .activate)
            .focusEffectDisabled()
            .onTapGesture { model?.showOverlay() }
            .accessibilityLabel("Show board controls")
    }

    private var overlay: some View {
        ViewerOverlay(panelName: model?.snapshot.panel?.name ?? "Panel",
                      onPanels: { model?.stop(); app.showPanels() },
                      onSettings: { model?.stop(); app.showSettings() })
    }

    /// Whether the board is the only thing a press could be aimed at.
    ///
    /// False whenever the viewer is showing chrome or a message of its own —
    /// each of those carries its own buttons, and they must win the focus.
    private var boardIsTheOnlyTarget: Bool {
        model?.overlayVisible != true
            && model?.resizeOfferVisible != true
            && model?.snapshot.deleted != true
            && model?.boardMissing != true
    }

    private var deletedState: some View {
        ViewerMessage(title: "This panel no longer exists",
                      detail: "It was deleted in the FiestaBoard app.",
                      primaryTitle: "Back to panels",
                      primaryAction: { model?.stop(); app.showPanels() })
    }

    private var missingBoardState: some View {
        ViewerMessage(title: "This panel's board is missing",
                      detail: "Reconnect the board in FiestaBoard, then return to this panel.",
                      primaryTitle: "Back to panels",
                      primaryAction: { model?.stop(); app.showPanels() })
    }

    /// Two ways out, and the offer exists to take the first one: resizing is
    /// primary, and "Later" just puts the board back.
    private var resizeOffer: some View {
        ViewerMessage(title: "This panel's grid doesn't suit this TV",
                      detail: "You can preview a new grid before resizing the panel.",
                      primaryTitle: "Resize for this TV",
                      primaryAction: openResizeSettings,
                      secondaryTitle: "Later",
                      secondaryAction: { model?.dismissResizeOffer() })
    }

    private func openResizeSettings() {
        model?.dismissResizeOffer()
        model?.stop()
        app.showSettings()
    }
}
