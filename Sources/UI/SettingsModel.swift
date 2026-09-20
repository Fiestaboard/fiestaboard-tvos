import Foundation
import Observation

@MainActor
@Observable
final class SettingsModel {

    static let presetDiagonals: [Double] = [32, 43, 50, 55, 65, 75, 85]

    var panels: [Panel] = []
    var isLoading = false
    var errorMessage: String?
    var warningMessage: String?
    var resizeDiagonal: Double = 65
    var sizing: BoardSizing = .fit

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
        if let raw = UserDefaults.standard.string(forKey: "fiestaboard.sizing"),
           let stored = BoardSizing(rawValue: raw) {
            sizing = stored
        }
    }

    var defaultPanelRef: String? { app.connection.saved?.defaultPanelRef }

    var boardName: String { app.connection.saved?.displayName ?? "Not connected" }

    var boardAddress: String { app.connection.saved?.host.absoluteString ?? "" }

    /// The grid `resizeDiagonal` would produce, computed locally so the
    /// change can be seen before the server reshapes anything.
    var previewGrid: String {
        guard let grid = try? BoardGeometry.computeAutofitGrid(diagonal: resizeDiagonal) else {
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
        } catch {
            errorMessage = "Couldn't reach your FiestaBoard."
        }
    }

    func setDefaultPanel(_ ref: String?) {
        app.connection.setDefaultPanel(ref: ref)
    }

    func setSizing(_ sizing: BoardSizing) {
        self.sizing = sizing
        UserDefaults.standard.set(sizing.rawValue, forKey: "fiestaboard.sizing")
    }

    func resize(panel: Panel) async {
        errorMessage = nil
        warningMessage = nil
        do {
            let result = try await app.connection.authorized {
                try await $0.updatePanel(id: panel.id, diagonal: resizeDiagonal)
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
        app.route = .signIn
    }

    func forget() {
        app.disconnect()
    }
}
