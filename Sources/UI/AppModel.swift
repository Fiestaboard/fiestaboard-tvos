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

    public let connection: ConnectionStore

    public init(connection: ConnectionStore) {
        self.connection = connection
    }

    /// Decide the opening screen. A configured TV should power on into its
    /// board — that is the whole point of the app.
    public func start() {
        guard let saved = connection.saved, connection.client != nil else {
            route = .connect
            return
        }
        if let ref = saved.defaultPanelRef {
            route = .viewer(ref)
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

    public func showPanels() {
        errorMessage = nil
        route = .panels
    }

    public func showSettings() {
        route = .settings
    }

    public func disconnect() {
        connection.forget()
        route = .connect
    }
}
