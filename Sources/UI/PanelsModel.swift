import Foundation
import Observation

@MainActor
@Observable
final class PanelsModel {
    var panels: [Panel] = []
    var isLoading = false
    var errorMessage: String?

    private let app: AppModel
    private var previewTask: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            panels = try await app.connection.authorized { try await $0.panels() }
            previewTask?.cancel()
            if let store = app.topShelfStore {
                let currentPanels = panels
                previewTask = Task {
                    await TopShelfPreviewPublisher.publish(panels: currentPanels,
                                                           connection: app.connection,
                                                           store: store)
                }
            }
        } catch FiestaError.unauthorized {
            // The stored credential could not recover the session — the only
            // useful next step is asking for one.
            app.route = .signIn
        } catch FiestaError.setupRequired {
            errorMessage = "This FiestaBoard has no account yet. Finish setup in the FiestaBoard app."
        } catch {
            errorMessage = "Couldn't reach your FiestaBoard. Check it's still on."
        }
    }
}
