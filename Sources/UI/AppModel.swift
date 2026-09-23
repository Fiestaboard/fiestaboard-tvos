import Foundation
import Observation

public enum Route: Equatable, Hashable {
    case connecting
    case connect
    case signIn
    case panels
    case viewer(String)
    case settings
}

/// Navigation and app-wide state.
///
/// The observable wrapper around Core, which is deliberately free of
/// Combine and Observation so it can be transcribed to Kotlin later.
@MainActor
@Observable
public final class AppModel {

    public var route: Route = .connecting
    public var errorMessage: String?
    var offeredResizeRefs: Set<String> = []
    private var previewTask: Task<Void, Never>?

    public let connection: ConnectionStore
    let topShelfStore: TopShelfSnapshotStore?

    public init(connection: ConnectionStore, topShelfStore: TopShelfSnapshotStore? = nil) {
        self.connection = connection
        self.topShelfStore = topShelfStore
    }

    /// Decide the opening screen. A configured TV should power on into its
    /// board — that is the whole point of the app.
    public func start() {
        guard route == .connecting else { return }
        guard let saved = connection.saved, connection.client != nil else {
            route = .connect
            return
        }
        if connection.isSignedOut {
            route = .signIn
            return
        }
        if let ref = saved.defaultPanelRef {
            route = .viewer(ref)
            refreshTopShelfForViewerLaunch()
        } else {
            route = .panels
        }
    }

    public func finishConnect(_ result: ConnectResult) {
        switch result {
        case .ready:
            errorMessage = nil
            route = .panels
        case .needsSignIn:
            errorMessage = nil
            route = .signIn
        case .needsSetup:
            // Only the web app can create the first account, so sending
            // someone to a sign-in form here would waste their time.
            errorMessage = "This FiestaBoard has no account yet. Finish setup in the FiestaBoard app, then connect again."
            route = .connect
        }
    }

    public func openPanel(ref: String) {
        errorMessage = nil
        route = .viewer(ref)
    }

    /// Opens `fiestaboard://panel/<ref>` from a Top Shelf carousel item.
    ///
    /// Exactly one path component, and only for a board this TV is still
    /// signed in to: the carousel can outlive the connection it was built
    /// from, and Home will happily send a stale link.
    public func openTopShelfURL(_ url: URL) {
        let components = url.path.split(separator: "/")
        guard url.scheme == "fiestaboard", url.host == "panel",
              components.count == 1,
              connection.saved != nil, connection.client != nil,
              !connection.isSignedOut else { return }
        openPanel(ref: String(components[0]))
        refreshTopShelfForViewerLaunch()
    }

    public func showPanels() {
        previewTask?.cancel()
        errorMessage = nil
        route = .panels
    }

    public func showSettings() {
        route = .settings
    }

    public func disconnect() {
        connection.forget()
        clearTopShelf()
        route = .connect
    }

    func clearTopShelf() {
        previewTask?.cancel()
        TopShelfPreviewPublisher.clear(store: topShelfStore)
    }

    private func refreshTopShelfForViewerLaunch() {
        guard let topShelfStore else { return }
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            guard let self,
                  let panels = try? await connection.authorized({ try await $0.panels() }),
                  !Task.isCancelled else { return }
            TopShelfPreviewPublisher.publish(panels: panels,
                                             connection: connection,
                                             store: topShelfStore)
        }
    }
}
