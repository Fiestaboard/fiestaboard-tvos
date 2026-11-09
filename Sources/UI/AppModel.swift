import Foundation
import Observation

public enum Route: Equatable, Hashable {
    case connecting
    case connect
    case signIn
    case deviceSignIn
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

    var oledCare: OLEDCareConfiguration
    var oledOutput = OLEDCareOutput()
    var oledTime = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private let oledStore: OLEDCareStore
    @ObservationIgnored private var oledSession = OLEDCareSession()
    @ObservationIgnored private var oledForeground = true
    @ObservationIgnored private var oledUnavailable = true
    @ObservationIgnored private var oledPanelDimmed = false

    func saveOLEDCare(_ value: OLEDCareConfiguration) {
        oledStore.save(value)
        oledCare = oledStore.load()
        applyScreenAwake()
    }

    func updateOLEDViewer(unavailable: Bool, panelDimmed: Bool) {
        oledUnavailable = unavailable
        oledPanelDimmed = panelDimmed
        applyScreenAwake()
    }

    func updateOLEDCare(now: Double = ProcessInfo.processInfo.systemUptime, date: Date = Date()) {
        oledTime = now
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let viewing: Bool
        if case .viewer = route { viewing = true } else { viewing = false }
        oledOutput = oledSession.update(oledCare, now: now, minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0),
            foreground: oledForeground, viewing: viewing, unavailable: oledUnavailable, panelDimmed: oledPanelDimmed)
        screenAwake.hold(oledOutput.keepAwake)
    }

    @discardableResult func interactWithOLED() -> Bool {
        let consumed = oledSession.interact(now: ProcessInfo.processInfo.systemUptime)
        applyScreenAwake()
        return consumed
    }

    public var errorMessage: String?
    var signInMessage: String?
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

    /// What this TV is called on the hub (A3, DD3). `.fallback` without the
    /// user-assigned-device-name entitlement (O6, owner-pending).
    public let deviceName: DeviceNameChoice

    /// A short notice over the current screen, such as "Approved by maya".
    public private(set) var notice: String?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    public init(connection: ConnectionStore, topShelfStore: TopShelfSnapshotStore? = nil, oledStore: OLEDCareStore = OLEDCareStore(),
                deviceName: DeviceNameChoice = .fallback) {
        self.deviceName = deviceName
        connection.deviceName = deviceName.sent
        self.oledStore = oledStore
        self.oledCare = oledStore.load()
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
            self?.oledForeground = true
            self?.applyScreenAwake()
            self?.refreshTopShelf()
        }
        screenAwake.onBackground = { [weak self] in
            self?.oledForeground = false
            self?.applyScreenAwake()
        }
    }

    /// Whether a board is on screen. The whole case for keeping the display
    /// awake is that a panel is being shown; anywhere else, the TV's own
    /// sleep settings are none of this app's business.
    var wantsScreenAwake: Bool {
        if case .viewer = route { return oledForeground && !oledCare.allowScreensaver && !oledOutput.resting }
        return false
    }

    /// Restate the wake request. Cheap, idempotent, and safe to call from
    /// anywhere — which is the point.
    func applyScreenAwake() {
        updateOLEDCare()
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

    func requestSignIn() {
        clearTopShelf()
        signInMessage = FiestaError.unauthorized.userMessage
        route = .signIn
        Announce.say(FiestaError.unauthorized.userMessage)
    }

    public func finishSignIn() {
        errorMessage = nil
        if let ref = connection.saved?.defaultPanelRef { route = .viewer(ref) }
        else { route = .panels }
    }

    /// Device-code sign-in finished; `approvedBy` is the approving user from
    /// `GET /auth/status`, or nil (no toast).
    public func finishSignIn(approvedBy: String?) {
        finishSignIn()
        if let approvedBy, !approvedBy.isEmpty { showNotice(TVCopy.DeviceSignIn.approvedBy(approvedBy)) }
    }

    /// Shows `text` for `duration`, and says it.
    public func showNotice(_ text: String, for duration: Duration = .seconds(4)) {
        noticeTask?.cancel()
        notice = text
        Announce.say(text)
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    public func openPanel(ref: String) {
        lastViewedPanelRef = ref
        errorMessage = nil
        route = .viewer(ref)
    }

    /// The hub's panel id or short-code shape (#24 S3): 1–64 ASCII letters,
    /// digits, `-` or `_`. A decoded `?`, `/`, `%` or `..` never qualifies.
    static func isPanelRef(_ ref: String) -> Bool {
        ref.range(of: "\\A[A-Za-z0-9_-]{1,64}\\z", options: .regularExpression) != nil
    }

    /// Opens `fiestaboard://panel/<ref>` from a Top Shelf carousel item.
    ///
    /// Exactly one path component, and only for a board this TV is still
    /// signed in to: the carousel can outlive the connection it was built
    /// from, and Home will happily send a stale link.
    /// A7: the carousel's More Info sends `fiestaboard://panels`, under the
    /// same guard.
    public func openTopShelfURL(_ url: URL) {
        let components = url.path.split(separator: "/")
        guard url.scheme == "fiestaboard",
              connection.saved != nil, connection.client != nil,
              !connection.isSignedOut else { return }
        // #24 S3: the carousel sends exactly two shapes. Anything else (a
        // query, a fragment, a user or port, another host) is refused.
        guard url.query == nil, url.fragment == nil, url.user == nil,
              url.password == nil, url.port == nil else { return }
        if url.host == "panels" {
            if components.isEmpty { showPanels() }
            return
        }
        guard url.host == "panel", components.count == 1,
              Self.isPanelRef(String(components[0])) else { return }
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

    @discardableResult
    public func disconnect() -> Task<Void, Never>? {
        connection.forget()
        let cleanup = clearTopShelf()
        route = .connect
        return cleanup
    }

    @discardableResult
    func clearTopShelf() -> Task<Void, Never>? {
        lastViewedPanelRef = nil
        beginTopShelfUpdate()
        panelReloadTask?.cancel()
        panelReloadTask = nil
        activePanelsModel = nil
        panelBrowserCache = nil
        topShelfImages.images.removeAll()
        resetTopShelfStatuses()
        lastTopShelf = nil
        topShelfClient = nil
        return TopShelfPreviewPublisher.clear(store: topShelfStore, cache: topShelfImages)
    }

    /// Invalidate outstanding list/frame replies before another refresh or
    /// a sign-out can change what Home is entitled to show.
    @discardableResult
    func beginTopShelfUpdate() -> UUID {
        previewTask?.cancel()
        previewTask = nil
        topShelfGeneration = UUID()
        topShelfImages.invalidate()
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
    @discardableResult
    func publishTopShelf(panels: [Panel], previews: [String: PanelPreviewState] = [:]) -> Task<Void, Never>? {
        guard let topShelfStore, connection.saved != nil, !connection.isSignedOut else { return nil }
        if topShelfClient !== connection.client {
            topShelfImages.invalidate()
            topShelfImages.images.removeAll()
            resetTopShelfStatuses()
        }
        topShelfClient = connection.client
        lastTopShelf = (panels, previews)
        refreshTopShelfStatuses(for: panels)
        let now = Date()
        let fresh = topShelfStatuses.filter { now.timeIntervalSince($0.value.at) <= TopShelfSnapshotStore.statusLifetime }
        return TopShelfPreviewPublisher.publish(panels: panels, previews: previews, statuses: fresh,
                                         connection: connection,
                                         store: topShelfStore, cache: topShelfImages)
    }

    // MARK: Top Shelf status (A7, after A6a)

    /// A status younger than this is reused rather than fetched again, so a
    /// burst of frame publications costs no status requests. Shorter than
    /// the store's 10-minute rule, so a TV in use keeps its line.
    static let topShelfStatusInterval: TimeInterval = 300
    /// The same four-at-a-time budget the frame fetcher uses.
    static let topShelfStatusConcurrency = 4
    static let hubRequestBudget = 4
    /// At most this many panels' statuses per refresh: `/panels` carries no
    /// status, so each one is its own `GET /panel/{id}` against a Pi.
    var topShelfStatusLimit = 12
    @ObservationIgnored private var topShelfStatuses: [String: TopShelfStatusReading] = [:]
    /// When each panel was last asked, successful or not: a failing hub is
    /// not asked again inside the interval either.
    @ObservationIgnored private var topShelfStatusAttempts: [String: Date] = [:]
    @ObservationIgnored private var lastTopShelf: (panels: [Panel], previews: [String: PanelPreviewState])?
    @ObservationIgnored private(set) var topShelfStatusTask: Task<Void, Never>?
    @ObservationIgnored private(set) var topShelfRepublication: Task<Void, Never>?

    /// A hub switch or sign-out: forget statuses and attempts, and let go of
    /// an old hub's in-flight fetch so the new hub's starts at once (#24 N2).
    private func resetTopShelfStatuses() {
        topShelfStatuses.removeAll()
        topShelfStatusAttempts.removeAll()
        topShelfStatusTask?.cancel()
        topShelfStatusTask = nil
        topShelfStatusTaskID = nil
        topShelfStatusesDeferred = false
    }

    /// A7b (#24 review S1): frames and statuses share the hub's four-request
    /// budget. While the panel browser's frame batch (four at a time) runs,
    /// status fetches wait; the batch's end starts them.
    @ObservationIgnored private var topShelfFrameBatches = 0
    @ObservationIgnored private var topShelfStatusesDeferred = false
    @ObservationIgnored private var topShelfStatusTaskID: UUID?

    func beginTopShelfFrameBatch() { topShelfFrameBatches += 1 }

    func endTopShelfFrameBatch() {
        topShelfFrameBatches = max(0, topShelfFrameBatches - 1)
        guard topShelfFrameBatches == 0, topShelfStatusesDeferred else { return }
        topShelfStatusesDeferred = false
        if let last = lastTopShelf, connection.client === topShelfClient { refreshTopShelfStatuses(for: last.panels) }
    }

    private func refreshTopShelfStatuses(for panels: [Panel]) {
        guard topShelfStatusTask == nil else { return }
        guard topShelfFrameBatches == 0 else { topShelfStatusesDeferred = true; return }
        let now = Date()
        let due = panels.filter { !$0.boardMissing }.prefix(topShelfStatusLimit).map(\.id).filter {
            topShelfStatusAttempts[$0].map { now.timeIntervalSince($0) >= Self.topShelfStatusInterval } ?? true
        }
        guard !due.isEmpty else { return }
        for id in due { topShelfStatusAttempts[id] = now }
        let client = connection.client
        let connection = connection
        let taskID = UUID()
        topShelfStatusTaskID = taskID
        topShelfStatusTask = Task { [weak self] in
            // A missing id: the fetch failed, so the previous status stands.
            // A nil status: the hub answered with nothing worth a line.
            let results = await Self.fetchTopShelfStatuses(due, connection: connection)
            guard let self, topShelfStatusTaskID == taskID else { return }
            topShelfStatusTask = nil
            topShelfStatusTaskID = nil
            guard !Task.isCancelled, connection.client === client, !connection.isSignedOut else { return }
            // #24 N1: each line is stamped with its own answer's time.
            for (id, answer) in results {
                topShelfStatuses[id] = answer.status.map { TopShelfStatusReading(status: $0, at: answer.at) }
            }
            // Re-confirmed lines are renewed on disk without a Home reload
            // (the store tells the two apart); a changed one reloads Home.
            if !results.isEmpty, let last = lastTopShelf {
                topShelfRepublication = publishTopShelf(panels: last.panels, previews: last.previews)
            }
        }
    }

    /// Four at a time; a failed fetch is left out of the result.
    nonisolated private static func fetchTopShelfStatuses(_ ids: [String], connection: ConnectionStore)
        async -> [String: (status: TopShelfStatus?, at: Date)] {
        await withTaskGroup(of: (String, TopShelfStatus?, Date?).self) { group in
            var pending = ids.makeIterator()
            func add(_ id: String) {
                group.addTask {
                    guard !Task.isCancelled,
                          let reading = try? await connection.authorized({ try await $0.panelReading(ref: id) })
                    else { return (id, nil, nil) }
                    let received = Date()
                    return (id, TopShelfStatus(reading: reading, receivedAt: received), received)
                }
            }
            for _ in 0..<topShelfStatusConcurrency {
                guard let id = pending.next() else { break }
                add(id)
            }
            var results: [String: (status: TopShelfStatus?, at: Date)] = [:]
            for await (id, status, received) in group {
                if let received { results[id] = (status, received) }
                if let next = pending.next() { add(next) }
            }
            return results
        }
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
