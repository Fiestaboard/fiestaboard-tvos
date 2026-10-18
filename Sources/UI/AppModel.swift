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

    /// Spelled out rather than left to `@Observable` so that every route
    /// change — including the ones other models make directly — passes
    /// through one place that can restate whether the TV may sleep.
    @ObservationIgnored private var storedRoute: Route = .connecting

    public var route: Route {
        get {
            access(keyPath: \.route)
            return storedRoute
        }
        set {
            withMutation(keyPath: \.route) { storedRoute = newValue }
            applyScreenAwake()
        }
    }

    public var errorMessage: String?
    var offeredResizeRefs: Set<String> = []
    var lastViewedPanelRef: String?
    /// Where Settings was opened from, so leaving it goes back there.
    private var routeBeforeSettings: Route?
    private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var panelReloadTask: Task<Void, Never>?
    @ObservationIgnored weak var activePanelsModel: PanelsModel?
    @ObservationIgnored var panelBrowserCache: PanelBrowserCache?
    @ObservationIgnored private(set) var topShelfGeneration = UUID()
    @ObservationIgnored private let topShelfImages = TopShelfPreviewPublisher.Cache()
    @ObservationIgnored private var topShelfClient: FiestaClient?

    public let connection: ConnectionStore
    let topShelfStore: TopShelfSnapshotStore?

    /// Holds the display awake while a board is up. Tests replace its sink.
    @ObservationIgnored let screenAwake: ScreenAwake

    public init(connection: ConnectionStore, topShelfStore: TopShelfSnapshotStore? = nil) {
        self.connection = connection
        self.topShelfStore = topShelfStore
        self.screenAwake = ScreenAwake()
        // A wake request is not a fact the system remembers on the app's
        // behalf. Coming back to the foreground, say what we want again.
        //
        // The card row is republished on the same beat, for the same reason:
        // it lives in the group container's `Library/Caches`, the only place
        // tvOS lets us write, and that is purgeable. Foreground is the one
        // moment the app is certainly running and certainly able to say what
        // Home should be showing.
        screenAwake.onForeground = { [weak self] in
            self?.applyScreenAwake()
            self?.refreshTopShelf()
        }
    }

    /// Whether a board is on screen. The whole case for keeping the display
    /// awake is that a panel is being shown; anywhere else, the TV's own
    /// sleep settings are none of this app's business.
    var wantsScreenAwake: Bool {
        if case .viewer = route { return true }
        return false
    }

    /// Restate the wake request. Cheap, idempotent, and safe to call from
    /// anywhere — which is the point.
    func applyScreenAwake() {
        screenAwake.hold(wantsScreenAwake)
    }

    /// Decide the opening screen. A configured TV should power on into its
    /// board — that is the whole point of the app.
    public func start() {
        // Also the app's first chance to state what it wants: a cold launch
        // straight into a board must not let the TV fall asleep on it.
        defer { applyScreenAwake() }
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
            refreshTopShelf()
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
            // someone to a sign-in form here would waste their time. The
            // wording lives with `FiestaError.setupRequired`, which is the
            // same state arriving from the other direction.
            errorMessage = FiestaError.setupRequired.userMessage
            route = .connect
        }
    }

    public func openPanel(ref: String) {
        lastViewedPanelRef = ref
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
        // No republish here. Opening a Top Shelf card brings the app to the
        // foreground, and the foreground hook above already refreshes — doing
        // it again on a cold launch into a default panel fired two panel
        // fetches at a Raspberry Pi a runloop turn apart.
        openPanel(ref: String(components[0]))
    }

    public func showPanels() {
        if case .viewer(let ref) = route { lastViewedPanelRef = ref }
        previewTask?.cancel()
        errorMessage = nil
        route = .panels
    }

    public func showSettings() {
        // Opening Settings twice must not lose the original origin.
        if route != .settings { routeBeforeSettings = route }
        route = .settings
    }

    /// Select the panel being watched when Settings opens. References may
    /// be either a panel id or its short code; the loaded panel list resolves it.
    var settingsPanelRef: String? {
        guard route == .settings, case .viewer(let ref) = routeBeforeSettings else { return nil }
        return ref
    }

    /// Leave Settings for wherever it was opened from.
    ///
    /// Settings is a destination reached from two different places, and tvOS
    /// has one Back button for both. Without an origin to return to, Menu
    /// fell through to the system and quit the app — so going Board →
    /// Settings → Back landed on the Apple TV home screen.
    public func dismissSettings() {
        let destination = routeBeforeSettings ?? .panels
        routeBeforeSettings = nil
        route = destination
    }

    public func disconnect() {
        connection.forget()
        clearTopShelf()
        route = .connect
    }

    func clearTopShelf() {
        lastViewedPanelRef = nil
        beginTopShelfUpdate()
        panelReloadTask?.cancel()
        panelReloadTask = nil
        activePanelsModel = nil
        panelBrowserCache = nil
        topShelfImages.images.removeAll()
        topShelfClient = nil
        TopShelfPreviewPublisher.clear(store: topShelfStore)
    }

    /// Invalidate outstanding list/frame replies before another refresh or
    /// a sign-out can change what Home is entitled to show.
    @discardableResult
    func beginTopShelfUpdate() -> UUID {
        previewTask?.cancel()
        previewTask = nil
        topShelfGeneration = UUID()
        return topShelfGeneration
    }

    func isCurrentTopShelfUpdate(_ generation: UUID, client: FiestaClient?) -> Bool {
        !Task.isCancelled && generation == topShelfGeneration && client != nil
            && connection.client === client && connection.saved != nil && !connection.isSignedOut
    }

    func rememberPanelBrowser(panels: [Panel], previews: [String: PanelPreviewState], client: FiestaClient?) {
        guard let client, connection.client === client, !connection.isSignedOut else { return }
        panelBrowserCache = PanelBrowserCache(client: client, panels: panels, previews: previews)
    }

    /// Publish the carousel from a panel list the caller already holds.
    ///
    /// `PanelsModel` owns the app's only fetch of the panel list, so this is
    /// the entry point it calls the moment the list lands. Without it, a TV
    /// whose owner never sets a default panel would never publish anything
    /// and Home would have no carousel at all.
    func publishTopShelf(panels: [Panel], previews: [String: PanelPreviewState] = [:]) {
        guard let topShelfStore, connection.saved != nil, !connection.isSignedOut else { return }
        if topShelfClient !== connection.client { topShelfImages.images.removeAll() }
        topShelfClient = connection.client
        TopShelfPreviewPublisher.publish(panels: panels, previews: previews,
                                         connection: connection,
                                         store: topShelfStore, cache: topShelfImages)
    }

    /// Fetch the panel list and republish the card row.
    ///
    /// For the paths that have no list to hand — a cold launch straight into
    /// a board, and every return to the foreground. Quiet on failure by
    /// design: the carousel is never worth a message on screen.
    func refreshTopShelf() {
        guard topShelfStore != nil else { return }
        // The visible panel grid owns its frame requests. Ask it to reload
        // both metadata and frames, so edits made while backgrounded appear
        // in the grid and Home through one shared four-at-a-time batch.
        if route == .panels {
            guard let activePanelsModel else { return } // Its first load is about to start.
            panelReloadTask?.cancel()
            panelReloadTask = Task { [weak activePanelsModel] in await activePanelsModel?.load() }
            return
        }
        let generation = beginTopShelfUpdate()
        let client = connection.client
        previewTask = Task { [weak self] in
            guard let self,
                  let panels = try? await connection.authorized({ try await $0.panels() }),
                  isCurrentTopShelfUpdate(generation, client: client) else { return }
            if panels.isEmpty { publishTopShelf(panels: []) }
            // The same four-at-a-time fetcher serves the grid and this path.
            // It publishes each completed frame, including truthful failures.
            await PanelsModel(app: self).refreshPreviews(for: panels)
        }
    }
}
