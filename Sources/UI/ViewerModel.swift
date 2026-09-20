import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class ViewerModel {

    var snapshot: PanelSnapshot = .empty
    var overlayVisible = false
    var sizing: BoardSizing = .fit

    private let app: AppModel
    private let ref: String
    private var store: PanelStore?
    private var pump: Task<Void, Never>?
    private var overlayTimer: Task<Void, Never>?

    /// How long the overlay stays up after a button press.
    static let overlayTimeout: TimeInterval = 4

    init(app: AppModel, ref: String) {
        self.app = app
        self.ref = ref
        if let raw = UserDefaults.standard.string(forKey: "fiestaboard.sizing"),
           let stored = BoardSizing(rawValue: raw) {
            sizing = stored
        }
    }

    func start() {
        guard let client = app.connection.client, store == nil else { return }
        let store = PanelStore(client: client, ref: ref)
        self.store = store
        pump = Task { [weak self] in
            for await snapshot in store.snapshots() {
                self?.snapshot = snapshot
            }
        }
    }

    func stop() {
        pump?.cancel(); pump = nil
        overlayTimer?.cancel(); overlayTimer = nil
        store?.stop(); store = nil
    }

    /// tvOS has focus, not a pointer, so the way "move the cursor to get
    /// back" translates is: any button wakes transient chrome, which fades.
    func showOverlay() {
        overlayVisible = true
        overlayTimer?.cancel()
        overlayTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.overlayTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.overlayVisible = false
        }
    }

    func setSizing(_ sizing: BoardSizing) {
        self.sizing = sizing
        UserDefaults.standard.set(sizing.rawValue, forKey: "fiestaboard.sizing")
    }

    func layout(for screen: CGSize) throws -> BoardLayout {
        guard let panel = snapshot.panel, snapshot.rows > 0, snapshot.cols > 0 else {
            throw BoardGeometry.Error.nonPositive("no panel yet")
        }
        return try BoardLayout.fitting(
            rows: snapshot.rows, cols: snapshot.cols, cells: snapshot.cells,
            in: screen, mode: sizing,
            diagonalInches: panel.screenDiagonalInches,
            calibration: panel.calibrationScale,
            colPitchIn: BoardGeometry.colPitchIn(deviceType: panel.deviceType))
    }

    /// Whether the panel's grid shape suits this screen closely enough that
    /// offering to re-fit it would be noise. Compares aspect, because size is
    /// what `fit` already absorbs and shape is what it cannot.
    func gridSuitsScreen(_ screen: CGSize) -> Bool {
        guard snapshot.rows > 0, snapshot.cols > 0, screen.height > 0 else { return true }
        let base = BoardLayout.make(rows: snapshot.rows, cols: snapshot.cols,
                                    cells: snapshot.cells, tileHeight: 100)
        guard base.height > 0 else { return true }
        let boardAspect = base.width / base.height
        let screenAspect = Double(screen.width / screen.height)
        // Within 25% is close enough that fit leaves no distracting margin.
        return abs(boardAspect - screenAspect) / screenAspect < 0.25
    }
}
