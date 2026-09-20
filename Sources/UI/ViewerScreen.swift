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
                // Board black, not pure black: matches the flaps behind it.
                BoardColor.black.swiftUI.ignoresSafeArea()

                if model?.snapshot.deleted == true {
                    deletedState
                } else if model?.boardMissing == true {
                    missingBoardState
                } else if let layout = try? model?.layout(for: proxy.size) {
                    BoardCanvas(layout: layout,
                                background: model?.snapshot.panel?.backgroundColor ?? .black,
                                animated: model?.snapshot.panel?.animationsEnabled ?? false)
                        .frame(width: layout.width, height: layout.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().tint(Fiesta.Colors.brand)
                }

                if model?.snapshot.connection == .stale { OfflineDot() }

                if model?.resizeOfferVisible == true {
                    resizeOffer
                }

                if model?.overlayVisible == true {
                    ViewerOverlay(panelName: model?.snapshot.panel?.name ?? "Panel",
                                  onPanels: { model?.stop(); app.showPanels() },
                                  onSettings: { model?.stop(); app.showSettings() })
                }
            }
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
            // A board on a wall must not be put to sleep by the TV.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            model?.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onMoveCommand { _ in model?.showOverlay() }
        .onPlayPauseCommand { model?.showOverlay() }
        .onExitCommand { model?.stop(); app.showPanels() }
    }

    private var deletedState: some View {
        VStack(spacing: 16) {
            Text("This panel no longer exists")
                .font(Fiesta.Text.heading)
                .foregroundStyle(Fiesta.Colors.foreground)
            Text("It was deleted in the FiestaBoard app.")
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
            FiestaButton("Back to panels") { model?.stop(); app.showPanels() }
                .frame(width: 420)
        }
    }

    private var missingBoardState: some View {
        VStack(spacing: 16) {
            Text("This panel's board is missing")
                .font(Fiesta.Text.heading)
                .foregroundStyle(Fiesta.Colors.foreground)
            Text("Reconnect the board in FiestaBoard, then return to this panel.")
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
            FiestaButton("Back to panels") { model?.stop(); app.showPanels() }
                .frame(width: 420)
        }
    }

    private var resizeOffer: some View {
        VStack(spacing: 18) {
            Text("This panel's grid doesn't suit this TV")
                .font(Fiesta.Text.heading)
                .foregroundStyle(Fiesta.Colors.foreground)
            Text("You can preview a new grid before resizing the panel.")
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
            HStack(spacing: 20) {
                FiestaButton("Resize for this TV") {
                    model?.dismissResizeOffer()
                    model?.stop()
                    app.showSettings()
                }
                FiestaButton("Later") { model?.dismissResizeOffer() }
            }
        }
        .padding(32)
        .background(Fiesta.Colors.surface)
    }
}
