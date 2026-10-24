import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class ViewerModel {

    var snapshot: PanelSnapshot = .empty
    var overlayVisible = false
    var resizeOfferVisible = false
    var sizing: BoardSizing = .fit
    private let localMatrixPresentation: MatrixPresentation
    let matrixTransitionStyle: MatrixTransitionStyle
    var matrixPresentation: MatrixPresentation { snapshot.panel?.effectiveMatrixPresentation(fallback: localMatrixPresentation) ?? localMatrixPresentation }
    var boardMissing: Bool { snapshot.panel?.boardMissing == true }

    /// Which panel this model is bound to.
    ///
    /// Readable, rather than private as it used to be: `.viewer(a)` and
    /// `.viewer(b)` are the same branch of `RootView`'s switch, so which panel
    /// a live model is actually showing is a question worth being able to ask.
    let ref: String

    private let app: AppModel
    private let isVoiceOverRunning: @MainActor () -> Bool
    // Machinery, not state anything draws — and `@ObservationIgnored` is
    // load-bearing on `pump`: the macro would otherwise make it a
    // main-actor-isolated computed property, which `deinit` cannot touch.
    @ObservationIgnored private var store: PanelStore?
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var overlayTimer: Task<Void, Never>?
    @ObservationIgnored private var preparedLayout: (key: LayoutKey, layout: BoardLayout)?

    private struct LayoutKey: Equatable {
        let rows: Int
        let cols: Int
        let cells: [[BoardCell]]
        let screen: CGSize
        let sizing: BoardSizing
        let diagonal: Double
        let calibration: Double
        let pitch: Double
    }

    /// How long the overlay stays up after a button press.
    static let overlayTimeout: TimeInterval = 4

    /// VoiceOver reads at its own pace and drives focus itself, so four
    /// seconds is not enough to hear the bar and then reach a button in it.
    ///
    /// Longer, but still finite: both overlay buttons navigate away and Menu
    /// leaves the viewer entirely, so a bar that never expires is a bar with
    /// no path back to a clean board.
    static let overlayTimeoutVoiceOver: TimeInterval = 20

    init(app: AppModel,
         ref: String,
         signage: SignageSettings = .shared,
         isVoiceOverRunning: @escaping @MainActor () -> Bool = { Announce.isVoiceOverRunning }) {
        self.app = app
        self.ref = ref
        localMatrixPresentation = signage.matrixPresentation
        matrixTransitionStyle = signage.matrixTransitionStyle
        self.isVoiceOverRunning = isVoiceOverRunning
        if let raw = UserDefaults.standard.string(forKey: "fiestaboard.sizing"),
           let stored = BoardSizing(rawValue: raw) {
            sizing = stored
        }
    }

    func start() {
        guard app.connection.client != nil, store == nil else { return }
        // Through `authorized`, never the bare client. This was the one place
        // in the app that polled with a raw client, so a session the board had
        // expired turned into a 401 every two seconds, forever, with the
        // viewer showing a spinner and an amber dot and nobody in the room.
        let store = PanelStore(runner: app.connection, ref: ref)
        self.store = store
        pump = Task { [weak self] in
            for await snapshot in store.snapshots() {
                self?.apply(snapshot)
            }
        }
    }

    /// Take a snapshot from the poll loop, and act on the two states that are
    /// about more than what is on screen.
    ///
    /// Internal rather than private so a test can drive it: both branches are
    /// about what the *next* launch does, which no render can show.
    func apply(_ snapshot: PanelSnapshot) {
        app.updateOLEDViewer(unavailable: snapshot.connection != .live || snapshot.deleted || snapshot.panel?.boardMissing == true,
                             panelDimmed: snapshot.dimmed)
        // The server routinely repeats the same frame. Observation otherwise
        // invalidates the entire viewer, including its canvases, every poll.
        if self.snapshot != snapshot { self.snapshot = snapshot }
        if snapshot.panel?.renderStyle == .ledMatrix, resizeOfferVisible { resizeOfferVisible = false }

        // A panel deleted on the server must stop being the panel this TV
        // opens into. Nothing else cleared the default, so the card explaining
        // what happened — right to show once — came back on every boot, and
        // the only recovery from the far side of a wall bracket was to delete
        // the app. Deliberately no navigation: the explanation stays up for
        // whoever is standing there.
        if snapshot.deleted, app.connection.saved?.defaultPanelRef == ref {
            app.connection.setDefaultPanel(ref: nil)
        }

        // Waiting does not mend a refused session, and the board is a
        // Raspberry Pi. Stop asking, and put someone in front of the form.
        if snapshot.connection == .unauthorized {
            stop()
            app.requestSignIn()
        }
    }

    func stop() {
        pump?.cancel(); pump = nil
        store?.stop(); store = nil
        // Chrome must not survive the board it was floating over.
        hideOverlay()
    }

    /// A model dropped without `stop()` — which is exactly what a route change
    /// under `ViewerScreen` used to do — must not leave a two-second poll
    /// running against the board for the life of the app.
    deinit { pump?.cancel() }

    // MARK: Overlay

    /// tvOS has focus, not a pointer, so the way "move the cursor to get
    /// back" translates is: any button wakes transient chrome, which fades.
    func showOverlay() {
        // The resize card owns remote focus until it is dismissed. Revealing
        // the toolbar here would compete with its secondary Later action.
        guard !resizeOfferVisible else { return }
        overlayVisible = true
        restartOverlayTimer()
    }

    /// Interaction *inside* the bar, which the board never sees.
    ///
    /// Once the bar is up, `wakeTarget` gives up its focusability, so a
    /// directional press consumed by the focus engine moving between Panels
    /// and Settings never reaches the screen's `onMoveCommand`. The bar's four
    /// seconds therefore ran out mid-interaction, every time.
    func keepOverlayAlive() {
        guard overlayVisible else { return }
        restartOverlayTimer()
    }

    func hideOverlay() {
        overlayTimer?.cancel(); overlayTimer = nil
        overlayVisible = false
    }

    /// How long the chrome has left. Internal so a test can pin both values.
    var overlayTimeout: TimeInterval {
        isVoiceOverRunning() ? Self.overlayTimeoutVoiceOver : Self.overlayTimeout
    }

    private func restartOverlayTimer() {
        overlayTimer?.cancel()
        let timeout = overlayTimeout
        overlayTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hideOverlay()
        }
    }

    // MARK: Board

    func setSizing(_ sizing: BoardSizing) {
        self.sizing = sizing
        UserDefaults.standard.set(sizing.rawValue, forKey: "fiestaboard.sizing")
    }

    func layout(for screen: CGSize) throws -> BoardLayout {
        guard let panel = snapshot.panel, snapshot.rows > 0, snapshot.cols > 0 else {
            throw BoardGeometry.Error.nonPositive("no panel yet")
        }
        let key = LayoutKey(rows: snapshot.rows, cols: snapshot.cols, cells: snapshot.cells,
                            screen: screen, sizing: sizing, diagonal: panel.screenDiagonalInches,
                            calibration: panel.calibrationScale,
                            pitch: BoardGeometry.colPitchIn(deviceType: panel.deviceType))
        if let preparedLayout, preparedLayout.key == key { return preparedLayout.layout }
        let layout = try BoardLayout.fitting(
            rows: snapshot.rows, cols: snapshot.cols, cells: snapshot.cells,
            in: screen, mode: sizing,
            diagonalInches: panel.screenDiagonalInches,
            calibration: panel.calibrationScale,
            colPitchIn: key.pitch)
        preparedLayout = (key, layout)
        return layout
    }

    /// Whether the panel's grid shape suits this screen closely enough that
    /// offering to re-fit it would be noise. Compares aspect, because size is
    /// what `fit` already absorbs and shape is what it cannot.
    func gridSuitsScreen(_ screen: CGSize) -> Bool {
        guard snapshot.rows > 0, snapshot.cols > 0, screen.height > 0 else { return true }
        let base = BoardLayout.size(rows: snapshot.rows, cols: snapshot.cols, tileHeight: 100)
        guard base.height > 0 else { return true }
        let boardAspect = base.width / base.height
        let screenAspect = Double(screen.width / screen.height)
        // Within 25% is close enough that fit leaves no distracting margin.
        return abs(boardAspect - screenAspect) / screenAspect < 0.25
    }

    func considerResizeOffer(for screen: CGSize) {
        guard snapshot.panel != nil, snapshot.panel?.renderStyle != .ledMatrix, !boardMissing, !snapshot.deleted,
              !gridSuitsScreen(screen), app.offeredResizeRefs.insert(ref).inserted else { return }
        resizeOfferVisible = true
    }

    func dismissResizeOffer() { resizeOfferVisible = false }
}
