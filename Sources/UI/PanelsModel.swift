import Foundation
import Observation

/// What a panel's board currently says, reduced to what a card needs.
///
/// Deliberately the frame's own `rows`/`cols` rather than the panel's: a
/// reshape in flight means the two disagree for a tick, and the frame is
/// the thing being drawn.
struct PanelPreview: Equatable, Sendable {
    let rows: Int
    let cols: Int
    let cells: [[BoardCell]]
    /// The frame's plain-text message, for VoiceOver. The board itself is
    /// `.accessibilityHidden` — 360 flaps is not browsable.
    let message: String?
    var richCells: [[MatrixCell]]? = nil

    static func make(from frame: PanelFrame, code62: Code62Glyph) -> PanelPreview {
        let cells: [[BoardCell]]
        if let characters = frame.characters {
            cells = BoardTables.cells(from: characters, code62: code62)
        } else {
            // A board with no characters yet is a board of blanks, which is
            // a truthful preview rather than a missing one.
            cells = []
        }
        return PanelPreview(rows: frame.rows, cols: frame.cols,
                            cells: cells, message: frame.message, richCells: frame.richCells)
    }
}

/// Where a card's picture has got to.
enum PanelPreviewState: Equatable, Sendable {
    case loading
    /// The board answered. This is what it says.
    case ready(PanelPreview)
    /// The board did not hand over a frame. The card stays; the picture
    /// does not. One panel failing is never the whole screen failing.
    case unavailable
}

/// In-memory only, and scoped to the exact connection that fetched it.
/// Returning from a viewer can show the last cards while refreshing them.
struct PanelBrowserCache {
    let client: FiestaClient
    let panels: [Panel]
    let previews: [String: PanelPreviewState]
}

@MainActor
@Observable
final class PanelsModel {
    var panels: [Panel] = []
    /// Keyed by panel id.
    var previews: [String: PanelPreviewState] = [:]
    var isLoading = false
    var errorMessage: String?

    /// Frames in flight at once. A board is a Raspberry Pi: firing one
    /// request per panel at it simultaneously is how a panel list with a
    /// dozen panels on it becomes a timeout.
    static let previewConcurrency = 4

    private let app: AppModel
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var previewGeneration = UUID()
    @ObservationIgnored private var previewClient: FiestaClient?
    @ObservationIgnored private var loadGeneration = UUID()

    init(app: AppModel) {
        self.app = app
        if let cached = app.panelBrowserCache, cached.client === app.connection.client,
           !app.connection.isSignedOut {
            panels = cached.panels
            previews = cached.previews
            previewClient = cached.client
        }
    }

    /// The picture to draw for `panel`, if any.
    func previewState(for panel: Panel) -> PanelPreviewState {
        previews[panel.id] ?? .unavailable
    }

    /// Fetch the panel list.
    ///
    /// The last attempt's message stays up until this one has finished.
    /// Clearing it here took the failure screen down the instant "Try
    /// again" was pressed — along with the button that had just been
    /// pressed, so focus fell back to the header and the next retry meant
    /// walking down the screen again.
    func load() async {
        guard !Task.isCancelled else { return }
        let generation = app.beginTopShelfUpdate()
        let load = UUID()
        loadGeneration = load
        let client = app.connection.client
        stopPreviews()
        app.activePanelsModel = self
        isLoading = true
        defer { if loadGeneration == load { isLoading = false } }
        do {
            let loaded = try await app.connection.authorized { try await $0.panels() }
            guard app.isCurrentTopShelfUpdate(generation, client: client) else { return }
            reconcile(loaded, client: client)
            errorMessage = nil
            // This is the app's only fetch of the panel list, so it is also
            // the app's only chance to keep Home's carousel honest. It used
            // to be published from the viewer-launch path alone, which meant
            // a TV whose owner never set a default panel published nothing,
            // ever — and the README claimed otherwise.
            // The list is on screen the moment it arrives; the pictures
            // catch up behind it.
            startPreviews(for: loaded)
            app.rememberPanelBrowser(panels: loaded, previews: previews, client: client)
            app.publishTopShelf(panels: loaded, previews: previews)
        } catch FiestaError.unauthorized {
            guard app.isCurrentTopShelfUpdate(generation, client: client) else { return }
            // The stored credential could not recover the session — the only
            // useful next step is asking for one. This attempt did not fail
            // with something to read, so an older message must not outlive
            // it on the screen behind the sign-in.
            errorMessage = nil
            app.route = .signIn
        } catch let error as FiestaError {
            guard app.isCurrentTopShelfUpdate(generation, client: client) else { return }
            fail(with: error.userMessage)
        } catch {
            guard app.isCurrentTopShelfUpdate(generation, client: client) else { return }
            fail(with: FiestaError.transport("\(error)").userMessage)
        }
    }

    /// Record the failure and say it out loud — see
    /// `Announce.say(_:recordingIn:)`.
    private func fail(with message: String) {
        Announce.say(message, recordingIn: &errorMessage)
    }

    /// Begin filling in the board pictures for `panels`.
    func startPreviews(for panels: [Panel]) {
        stopPreviews()
        app.activePanelsModel = self
        seedPreviews(for: panels)
        let generation = app.topShelfGeneration
        let client = app.connection.client
        previewTask = Task { [weak self] in
            guard let self, app.isCurrentTopShelfUpdate(generation, client: client) else { return }
            await refreshPreviews(for: panels)
        }
    }

    /// Stop fetching frames — the screen has gone away.
    func stopPreviews() {
        previewTask?.cancel()
        previewTask = nil
        previewGeneration = UUID()
        if app.activePanelsModel === self { app.activePanelsModel = nil }
    }

    /// Fetch every panel's current frame, a few at a time, publishing each
    /// as it lands so the grid fills in rather than appearing all at once.
    func refreshPreviews(for panels: [Panel]) async {
        // A panel with no board has nothing to preview; asking for its
        // frame is a round trip that can only 404.
        let targets = panels.filter { !$0.boardMissing }
        let connection = app.connection
        let client = connection.client
        let generation = app.topShelfGeneration
        let run = previewGeneration
        guard app.isCurrentTopShelfUpdate(generation, client: client) else { return }
        reconcile(panels, client: client)
        seedPreviews(for: panels)
        guard !targets.isEmpty else {
            app.rememberPanelBrowser(panels: panels, previews: [:], client: client)
            app.publishTopShelf(panels: panels)
            return
        }

        await withTaskGroup(of: (String, PanelPreviewState).self) { group in
            var pending = targets.makeIterator()
            var started = 0
            while started < Self.previewConcurrency, let panel = pending.next() {
                group.addTask { await Self.fetchPreview(for: panel, connection: connection) }
                started += 1
            }
            while let result = await group.next() {
                if run != previewGeneration || !app.isCurrentTopShelfUpdate(generation, client: client) {
                    group.cancelAll()
                    continue
                }
                previews[result.0] = result.1
                app.rememberPanelBrowser(panels: panels, previews: previews, client: client)
                app.publishTopShelf(panels: panels, previews: previews)
                if let next = pending.next() {
                    group.addTask { await Self.fetchPreview(for: next, connection: connection) }
                }
                // Several completed frames can be waiting in the group.
                // Give focus/input a turn between static image renders.
                await Task.yield()
            }
        }
    }

    /// Everything without a picture yet shows as loading; a picture we
    /// already have stays up while its replacement is fetched, so coming
    /// back from the viewer does not blank the grid.
    private func seedPreviews(for panels: [Panel]) {
        var seeded: [String: PanelPreviewState] = [:]
        for panel in panels where !panel.boardMissing {
            if case .ready = previews[panel.id] {
                seeded[panel.id] = previews[panel.id]
            } else {
                seeded[panel.id] = .loading
            }
        }
        if previews != seeded { previews = seeded }
    }

    /// A panel can be reassigned to a different board while this TV is away.
    /// Reuse only frames belonging to the same panel/board pair, including
    /// when the refresh was launched from the viewer instead of the grid.
    private func reconcile(_ loaded: [Panel], client: FiestaClient?) {
        let previousBoards = Dictionary(panels.map { ($0.id, $0.boardId) },
                                        uniquingKeysWith: { _, last in last })
        let retainedIDs = Set(loaded.filter { previousBoards[$0.id] == $0.boardId }.map(\.id))
        let retained = previewClient === client ? previews.filter { retainedIDs.contains($0.key) } : [:]
        if previews != retained { previews = retained }
        previewClient = client
        if panels != loaded { panels = loaded }
    }

    /// Off the main actor: this is a network round trip per panel.
    private nonisolated static func fetchPreview(
        for panel: Panel, connection: ConnectionStore
    ) async -> (String, PanelPreviewState) {
        do {
            let frame = try await connection.authorized { try await $0.frame(ref: panel.id) }
            let preview = PanelPreview.make(from: frame, code62: panel.effectiveCode62)
            return (panel.id, .ready(preview))
        } catch {
            // Never surfaced as the screen's error: the panel list loaded,
            // and a card without a picture is still a usable card.
            return (panel.id, .unavailable)
        }
    }
}
