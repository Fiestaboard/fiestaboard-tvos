import SwiftUI

struct ViewerScreen: View {
    let ref: String
    @Environment(AppModel.self) private var app
    @State private var model: ViewerModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Test seam: the screen builds its own model, and a harness has no other
    /// way to see which panel the model it built is bound to — which is
    /// precisely what went wrong for as long as this screen has existed.
    private let onModel: ((ViewerModel) -> Void)?

    /// Injectable so render tests can drive a fixed snapshot.
    init(ref: String,
         model: ViewerModel? = nil,
         onModel: ((ViewerModel) -> Void)? = nil) {
        self.ref = ref
        _model = State(initialValue: model)
        self.onModel = onModel
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Switch off OLED pixels outside the lit flaps. Deliberately
                // outside the dim and the drift below: dimming true black
                // achieves nothing, and drifting it slid the ground aside to
                // expose eight points of #0e0d0b along two edges — a crawling
                // grey band on the one screen contracted to be true black.
                Color.black.ignoresSafeArea()

                if !app.oledOutput.resting {
                    if model?.snapshot.deleted == true {
                        deletedState.opacity(app.oledOutput.brightness)
                    } else if model?.boardMissing == true {
                        missingBoardState.opacity(app.oledOutput.brightness)
                    } else {
                        boardLayer(in: proxy.size)
                    }
                    if model?.snapshot.connection == .stale {
                        offlineIndicator.opacity(app.oledOutput.brightness)
                    }
                    if model?.resizeOfferVisible == true { resizeOffer }
                    if model?.overlayVisible == true { overlay }
                }
                if app.oledOutput.resting || boardIsTheOnlyTarget { wakeTarget }

            }
            // Scoped to one value each. A blanket animation here would take
            // the 810-tile Canvas and the focus layout with it; these fire
            // only for the chrome, and without them the one transition the
            // app declares never ran at all.
            .animation(.easeInOut(duration: 0.22), value: model?.overlayVisible)
            .animation(.easeOut(duration: 0.28), value: model?.resizeOfferVisible)
            .onChange(of: [model?.snapshot.rows ?? 0, model?.snapshot.cols ?? 0]) { _, _ in
                model?.considerResizeOffer(for: proxy.size)
            }
            .onChange(of: proxy.size) { _, _ in model?.considerResizeOffer(for: proxy.size) }
        }
        .ignoresSafeArea()
        .onAppear {
            bind(model ?? ViewerModel(app: app, ref: ref))
            // Keeping the TV awake is AppModel's job, not this view's: it
            // follows the route, so it cannot be lost to the ordering
            // between one screen's onDisappear and the next one's onAppear.
        }
        // `.viewer(a)` and `.viewer(b)` are the same branch of RootView's
        // switch, so SwiftUI keeps this view — and its `@State` model — alive
        // across the change. `onAppear` does not fire again and `start()`
        // second-locks on the store it already has, so every Top Shelf jump
        // opened the board you were already looking at, and a TV with a
        // default panel ignored the URL entirely. Teardown is spelled out
        // rather than left to `.id(ref)`: this screen does not trust the
        // ordering between one appearance and the next, and it should not
        // have to start trusting it here either.
        .onChange(of: ref) { _, new in
            model?.stop()
            bind(ViewerModel(app: app, ref: new))
        }
        .onDisappear { model?.stop() }
        .onMoveCommand { _ in remoteInteraction() }
        .onPlayPauseCommand { remoteInteraction() }
        .onExitCommand { if app.interactWithOLED() { model?.showOverlay() } else { model?.stop(); app.showPanels() } }
        // The indicators are the only sign the board stopped answering, and a
        // sign is no use to VoiceOver: nothing about them takes focus.
        .onChange(of: model?.snapshot.connection) { old, new in announce(from: old, to: new) }
    }

    private func bind(_ fresh: ViewerModel) {
        model = fresh
        app.updateOLEDViewer(unavailable: fresh.snapshot.connection != .live || fresh.snapshot.deleted || fresh.boardMissing,
                             panelDimmed: fresh.snapshot.dimmed)
        fresh.start()
        onModel?(fresh)
    }

    private func announce(from old: ConnectionState?, to new: ConnectionState?) {
        switch (old, new) {
        case (.stale?, .live?):
            Announce.say("Reconnected to FiestaBoard.")
        case (_, .stale?):
            Announce.say("Disconnected from FiestaBoard. Showing the last message.")
        // No arm for `.unauthorized`: see the chrome stack in `body`. This
        // view is gone in the same update that sets the state, so the arm
        // that used to be here announced from a view nobody was on.
        default:
            break
        }
    }

    // MARK: Layers
    //
    // Each branch of the stack is its own property, which is worth it for
    // reading. It is not worth defending on build time, whatever an IDE says:
    // this split was once written up as a type-checker fix on the strength of
    // a SourceKit warning and no measurement. Measured, `body` type-checks in
    // 18ms as it stands and 42ms with every branch inlined — a real shape
    // (several conditionals and a throwing call in one expression) at a cost
    // three orders of magnitude under the hazard docs/tvos-design.md records,
    // whose symptom is a file that will not compile at all. That doc carries
    // the one-line command that produced both numbers.

    /// The board itself, and nothing else: this is the only thing the night
    /// dim and the burn-in drift are allowed to touch.
    private func remoteInteraction() {
        app.interactWithOLED()
        model?.showOverlay()
    }

    private func boardLayer(in size: CGSize) -> some View {
        let g = OLEDCareGeometry(width: size.width, height: size.height, config: app.oledCare,
                                 rotating: app.oledOutput.rotating, placement: app.oledOutput.placement,
                                 elapsed: app.oledTime, reduceMotion: reduceMotion)
        return board(in: CGSize(width: g.width, height: g.height), fullSize: size)
            .frame(width: g.width, height: g.height)
            .position(x: g.x, y: g.y)
            .opacity(app.oledOutput.brightness)
    }

    private var isMatrix: Bool {
        model?.snapshot.panel?.renderStyle == .ledMatrix
    }

    @ViewBuilder
    private func board(in size: CGSize, fullSize: CGSize) -> some View {
        if model?.snapshot.deleted == true {
            deletedState
        } else if model?.boardMissing == true {
            missingBoardState
        } else if let snapshot = model?.snapshot, let panel = snapshot.panel, panel.renderStyle == .ledMatrix {
            MatrixCanvas(raster: MatrixRaster.make(panel: panel, cells: snapshot.cells, richCells: snapshot.richCells, layers: snapshot.layers),
                         display: panel.matrixDisplay, presentation: matrixPresentation(in: size, fullSize: fullSize),
                         drift: .zero, animated: panel.animationsEnabled,
                         transitionStyle: model?.matrixTransitionStyle ?? .characterWipe)
        } else if let layout = try? model?.layout(for: model?.sizing == .trueScale ? fullSize : size) {
            canvas(for: layout)
                .scaleEffect(min(1, min(size.width / layout.width, size.height / layout.height)))
        } else {
            TacoLoader(size: .large)
        }
    }

    private func matrixPresentation(in size: CGSize, fullSize: CGSize) -> MatrixPresentation {
        let presentation = model?.matrixPresentation ?? .init()
        guard presentation.sizing == .trueSize else { return presentation }
        let ratio = hypot(size.width, size.height) / hypot(fullSize.width, fullSize.height)
        return MatrixPresentation(sizing: .trueSize, diagonalInches: presentation.diagonalInches * ratio,
                                  pitchMillimeters: presentation.pitchMillimeters, calibrationScale: presentation.calibrationScale)
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
    ///
    /// It is also where the board speaks. `BoardCanvas` hides itself from
    /// VoiceOver — 810 elements is not something anyone can browse — under a
    /// comment saying the viewer announces the flip, and for a long time the
    /// viewer did not hold up its end. One element, and it is this one: a
    /// second full-screen focusable is the mistake described above.
    private var wakeTarget: some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable(app.oledOutput.resting || boardIsTheOnlyTarget, interactions: .activate)
            .focusEffectDisabled()
            .onTapGesture { remoteInteraction() }
            .accessibilityElement()
            .accessibilityAddTraits([.isButton, .updatesFrequently])
            .accessibilityLabel(model?.snapshot.panel?.name ?? "FiestaBoard")
            .accessibilityValue(spokenBoard)
            .accessibilityHint("Shows Panels and Settings.")
    }

    private var spokenBoard: String {
        let board = model?.snapshot.spokenContent ?? "Connecting."
        guard model?.snapshot.dimmed == true else { return board }
        // Otherwise the board reads the same at night as it does by day,
        // while the room can see it is at a third brightness.
        return board + ". Dimmed for the night."
    }

    private var overlay: some View {
        ViewerOverlay(panelName: model?.snapshot.panel?.name ?? "Panel",
                      onInteraction: { model?.keepOverlayAlive() },
                      onPanels: { model?.stop(); app.showPanels() },
                      onSettings: { model?.stop(); app.showSettings() },
                      onFiestaBot: app.connection.usesDeviceCredential ? nil : {
                          if app.showFiestaBot() { model?.stop() }
                      })
    }

    /// Amber, and the words say the app is still trying: the frame on the
    /// flaps is still true, it is only out of date.
    private var offlineIndicator: some View {
        BoardStatusPill(title: "Reconnecting",
                        systemImage: "wifi.exclamationmark",
                        tint: Fiesta.Colors.offline,
                        spoken: "Disconnected from FiestaBoard. Showing the last message.")
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

    /// "Deleted in the FiestaBoard app" was circular: the icon this is running
    /// under is labelled FiestaBoard. Panels are managed on the board's own
    /// web page, so that is where the sentence points — see `Models.swift`,
    /// which argues the same rule out for the setup copy.
    private var deletedState: some View {
        ViewerMessage(title: "This panel no longer exists",
                      detail: "It was deleted on your board's web page.",
                      primaryTitle: "Back to panels",
                      primaryAction: { model?.stop(); app.showPanels() })
    }

    /// `board_missing` is the server saying the board row was *deleted*, so
    /// "reconnect the board" prescribed an action that does not exist. And
    /// the recreating happens on the board's web page, not in "the FiestaBoard
    /// app" — which is the icon the person reading this is standing in.
    private var missingBoardState: some View {
        ViewerMessage(title: "This panel's board was removed",
                      detail: "The virtual board behind this panel was deleted. "
                            + "Open your board's web page in a browser on a phone or "
                            + "computer to delete and recreate the panel.",
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
