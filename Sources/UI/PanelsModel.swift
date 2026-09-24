import Foundation
import Observation

@MainActor
@Observable
final class PanelsModel {
    var panels: [Panel] = []
    var isLoading = false
    var errorMessage: String?

    private let app: AppModel

    init(app: AppModel) { self.app = app }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            panels = try await app.connection.authorized { try await $0.panels() }
            if let store = app.topShelfStore {
                TopShelfPreviewPublisher.publish(panels: panels,
                                                 connection: app.connection,
                                                 store: store)
            }
        } catch FiestaError.unauthorized {
            // The stored credential could not recover the session — the only
            // useful next step is asking for one.
            app.route = .signIn
        } catch let error as FiestaError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = FiestaError.transport("\(error)").userMessage
        }
    }
}
