import Foundation
import Observation

@MainActor
@Observable
final class SettingsModel {

    static let presetDiagonals: [Double] = [32, 43, 50, 55, 65, 75, 85]
    private static let tvAspectW = 16.0
    private static let tvAspectH = 9.0

    var panels: [Panel] = []
    var isLoading = false
    var errorMessage: String?
    var warningMessage: String?
    var resizeDiagonal: Double = 65
    var customDiagonalText = ""
    var sizing: BoardSizing = .fit
    var defaultPanelRef: String?
    private var calibrations: [String: Double] = [:]
    /// Switches the user has flipped but the board has not confirmed yet.
    private var pendingAnimation: [String: Bool] = [:]

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
        defaultPanelRef = app.connection.saved?.defaultPanelRef
        if let raw = UserDefaults.standard.string(forKey: "fiestaboard.sizing"),
           let stored = BoardSizing(rawValue: raw) {
            sizing = stored
        }
    }

    var boardName: String { app.connection.saved?.displayName ?? "Not connected" }

    var boardAddress: String { app.connection.saved?.host.absoluteString ?? "" }

    private var customDiagonalIsValid: Bool {
        customDiagonalText.isEmpty || (Double(customDiagonalText).map { $0 > 0 } ?? false)
    }

    /// The grid `resizeDiagonal` would produce, computed locally so the
    /// change can be seen before the server reshapes anything.
    var previewGrid: String {
        guard customDiagonalIsValid else { return "—" }
        guard let grid = try? BoardGeometry.computeAutofitGrid(
            diagonal: resizeDiagonal, aspectW: Self.tvAspectW, aspectH: Self.tvAspectH) else {
            return "—"
        }
        return "\(grid.notesWide * BoardGeometry.noteCols) × \(grid.notesTall * BoardGeometry.noteRows)"
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            panels = try await app.connection.authorized { try await $0.panels() }
        } catch FiestaError.unauthorized {
            app.route = .signIn
        } catch let error as FiestaError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = FiestaError.transport("\(error)").userMessage
        }
    }

    func setDefaultPanel(_ ref: String?) {
        app.connection.setDefaultPanel(ref: ref)
        defaultPanelRef = ref
    }

    func setSizing(_ sizing: BoardSizing) {
        self.sizing = sizing
        UserDefaults.standard.set(sizing.rawValue, forKey: "fiestaboard.sizing")
    }

    /// Whether this panel's flaps animate.
    ///
    /// Read from the loaded list rather than from the `Panel` the caller is
    /// holding: a row built earlier hands back a value copied at build time,
    /// which goes stale as soon as anything updates the list, and the switch
    /// then sits on the old state.
    ///
    /// A flip the board has not confirmed yet wins over both, so the switch
    /// moves under the thumb instead of after a round trip.
    func animationEnabled(for panel: Panel) -> Bool {
        if let pending = pendingAnimation[panel.id] { return pending }
        return panels.first(where: { $0.id == panel.id })?.animationsEnabled
            ?? panel.animationsEnabled
    }

    func setAnimationEnabled(_ enabled: Bool, for panel: Panel) async {
        errorMessage = nil
        pendingAnimation[panel.id] = enabled
        // However this ends, the switch goes back to describing the board.
        defer { pendingAnimation[panel.id] = nil }
        do {
            let result = try await app.connection.authorized {
                try await $0.updatePanel(id: panel.id, animationsEnabled: enabled)
            }
            if let index = panels.firstIndex(where: { $0.id == panel.id }) {
                panels[index] = result.panel
            }
        } catch FiestaError.unauthorized {
            app.route = .signIn
        } catch let error as FiestaError {
            errorMessage = "Couldn't save the animation setting. " + error.userMessage
        } catch {
            errorMessage = "Couldn't save the animation setting."
        }
    }

    func selectPreset(_ inches: Double) {
        resizeDiagonal = inches
        customDiagonalText = ""
    }

    func setCustomDiagonal(_ raw: String) {
        customDiagonalText = raw
        if let value = Double(raw), value > 0 { resizeDiagonal = value }
    }

    func calibration(for panel: Panel) -> Double {
        calibrations[panel.id] ?? min(1.15, max(0.85, panel.calibrationScale))
    }

    func setCalibration(_ value: Double, for panel: Panel) {
        calibrations[panel.id] = min(1.15, max(0.85, value))
    }

    func saveCalibration(panel: Panel) async {
        errorMessage = nil
        do {
            let scale = calibration(for: panel)
            _ = try await app.connection.authorized {
                try await $0.updatePanel(id: panel.id, calibration: scale)
            }
        } catch FiestaError.unauthorized {
            app.route = .signIn
        } catch let error as FiestaError {
            errorMessage = "Couldn't save the calibration. " + error.userMessage
        } catch {
            errorMessage = "Couldn't save the calibration."
        }
    }

    func resize(panel: Panel) async {
        errorMessage = nil
        warningMessage = nil
        guard customDiagonalIsValid else {
            errorMessage = "Enter a positive screen size in inches."
            return
        }
        do {
            let result = try await app.connection.authorized {
                try await $0.updatePanel(id: panel.id, diagonal: resizeDiagonal,
                                         aspectW: Self.tvAspectW, aspectH: Self.tvAspectH)
            }
            if !result.incompatibleReferences.isEmpty {
                let count = result.incompatibleReferences.count
                let noun = count == 1 ? "page was" : "pages were"
                warningMessage = "The grid changed. \(count) \(noun) authored for the old size and won't fill this one — edit them in the FiestaBoard app."
            }
            await load()
        } catch FiestaError.unauthorized {
            app.route = .signIn
        } catch {
            errorMessage = "Couldn't resize this panel."
        }
    }

    func signOut() {
        app.connection.signOut()
        app.clearTopShelf()
        app.route = .signIn
    }

    func forget() {
        app.disconnect()
    }
}
