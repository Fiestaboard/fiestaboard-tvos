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

    /// The read-only status chip (A6b), recomputed on every snapshot so its
    /// countdown ticks; stored only when it changes.
    private(set) var statusChip: StatusChipContent?
    /// Whether the chip shows on its own, with the overlay down.
    private(set) var chipStandaloneVisible = false

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
    @ObservationIgnored private var chipPresenter = StatusChipPresenter()
    @ObservationIgnored private var reconnectedUntil: Date?
    @ObservationIgnored private var chipTimer: Task<Void, Never>?
    private let now: () -> Date

    private struct LayoutKey: Equatable {
        let rows: Int
        let cols: Int
        let cells: [[BoardCell]]
        let screen: CGSize
        let sizing: BoardSizing
        let diagonal: Double
        let calibration: Double
        let pitch: Double
        let noteArray: Bool
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
         isVoiceOverRunning: @escaping @MainActor () -> Bool = { Announce.isVoiceOverRunning },
         now: @escaping () -> Date = Date.init) {
        self.app = app
        self.now = now
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
        // Back from an outage: the chip says "Reconnected" for a moment (DD22).
        if self.snapshot.connection == .stale, snapshot.connection == .live {
            reconnectedUntil = now().addingTimeInterval(StatusChipPresenter.reconnectedFor)
        }
        // The server routinely repeats the same frame. Observation otherwise
        // invalidates the entire viewer, including its canvases, every poll.
        if self.snapshot != snapshot { self.snapshot = snapshot }
        refreshChip()
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
        chipTimer?.cancel(); chipTimer = nil
        pump?.cancel(); pump = nil
        store?.stop(); store = nil
        // Chrome must not survive the board it was floating over.
        hideOverlay()
    }

    /// A model dropped without `stop()` — which is exactly what a route change
    /// under `ViewerScreen` used to do — must not leave a two-second poll
    /// running against the board for the life of the app.
    deinit { pump?.cancel(); chipTimer?.cancel() }

    // MARK: Status chip

    /// Recompute the chip at the model's clock: what it says, whether that is
    /// news (shown on its own for a while and said once), and whether it shows
    /// on its own now. Called on every snapshot and at the chip's deadlines.
    func refreshChip() {
        let at = now()
        let reconnected = reconnectedUntil.map { at < $0 } ?? false
        // A deleted panel or a removed board has no hub status worth naming,
        // but an outage still shows and is said (#25 review must-fix).
        let content = snapshot.statusChip(localNow: at, reconnected: reconnected, timeZone: .current,
                                          includingStatus: !(snapshot.deleted || boardMissing))
        if chipPresenter.update(content, at: at), let content {
            Announce.say(StatusChipPresenter.spoken(content, panelName: snapshot.panel?.name ?? "Panel"))
        }
        if statusChip != content { statusChip = content }
        updateChipVisibility(at: at)
        scheduleChipRefresh(after: at, reconnected: reconnected)
    }

    private func updateChipVisibility(at: Date) {
        let visible = chipPresenter.standaloneVisible(at: at, overlayVisible: overlayVisible)
        if chipStandaloneVisible != visible { chipStandaloneVisible = visible }
    }

    /// Wake for the 6 s window or the end of "Reconnected", whichever is next.
    private func scheduleChipRefresh(after at: Date, reconnected: Bool) {
        chipTimer?.cancel(); chipTimer = nil
        let deadlines = [chipPresenter.nextDeadline, reconnected ? reconnectedUntil : nil].compactMap { $0 }.filter { $0 > at }
        guard let next = deadlines.min() else { return }
        let delay = next.timeIntervalSince(at)
        chipTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.refreshChip()
        }
    }

    // MARK: Overlay

    /// tvOS has focus, not a pointer, so the way "move the cursor to get
    /// back" translates is: any button wakes transient chrome, which fades.
    func showOverlay() {
        // The resize card owns remote focus until it is dismissed. Revealing
        // the toolbar here would compete with its secondary Later action.
        guard !resizeOfferVisible else { return }
        overlayVisible = true
        updateChipVisibility(at: now())
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
        updateChipVisibility(at: now())
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
                            pitch: BoardGeometry.colPitchIn(deviceType: panel.deviceType),
                            noteArray: panel.isNoteArray)
        if let preparedLayout, preparedLayout.key == key { return preparedLayout.layout }
        let layout = try BoardLayout.fitting(
            rows: snapshot.rows, cols: snapshot.cols, cells: snapshot.cells,
            in: screen, mode: sizing,
            diagonalInches: panel.screenDiagonalInches,
            calibration: panel.calibrationScale,
            colPitchIn: key.pitch,
            noteArray: key.noteArray)
        preparedLayout = (key, layout)
        return layout
    }

    /// Whether the panel's grid shape suits this screen closely enough that
    /// offering to re-fit it would be noise. Compares aspect, because size is
    /// what `fit` already absorbs and shape is what it cannot.
    func gridSuitsScreen(_ screen: CGSize) -> Bool {
        guard snapshot.rows > 0, snapshot.cols > 0, screen.height > 0 else { return true }
        // Within 25% is close enough that fit leaves no distracting margin.
        return BoardLayout.gridSuits(rows: snapshot.rows, cols: snapshot.cols,
                                     noteArray: snapshot.panel?.isNoteArray == true, screen: screen)
    }

    func considerResizeOffer(for screen: CGSize) {
        guard snapshot.panel != nil, snapshot.panel?.renderStyle != .ledMatrix, !boardMissing, !snapshot.deleted,
              !gridSuitsScreen(screen), app.offeredResizeRefs.insert(ref).inserted else { return }
        hideOverlay()
        resizeOfferVisible = true
    }

    func dismissResizeOffer() { resizeOfferVisible = false }
}
