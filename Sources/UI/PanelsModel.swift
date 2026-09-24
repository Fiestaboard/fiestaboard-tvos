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
                            cells: cells, message: frame.message)
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

    init(app: AppModel) { self.app = app }

    /// The picture to draw for `panel`, if any.
    func previewState(for panel: Panel) -> PanelPreviewState {
        previews[panel.id] ?? .unavailable
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await app.connection.authorized { try await $0.panels() }
            panels = loaded
            if let store = app.topShelfStore {
                TopShelfPreviewPublisher.publish(panels: loaded,
                                                 connection: app.connection,
                                                 store: store)
            }
            // The list is on screen the moment it arrives; the pictures
            // catch up behind it.
            startPreviews(for: loaded)
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

    /// Begin filling in the board pictures for `panels`.
    func startPreviews(for panels: [Panel]) {
        previewTask?.cancel()
        seedPreviews(for: panels)
        previewTask = Task { [weak self] in await self?.refreshPreviews(for: panels) }
    }

    /// Stop fetching frames — the screen has gone away.
    func stopPreviews() {
        previewTask?.cancel()
        previewTask = nil
    }

    /// Fetch every panel's current frame, a few at a time, publishing each
    /// as it lands so the grid fills in rather than appearing all at once.
    func refreshPreviews(for panels: [Panel]) async {
        // A panel with no board has nothing to preview; asking for its
        // frame is a round trip that can only 404.
        let targets = panels.filter { !$0.boardMissing }
        guard !targets.isEmpty else { return }
        let connection = app.connection

        await withTaskGroup(of: (String, PanelPreviewState).self) { group in
            var pending = targets.makeIterator()
            var started = 0
            while started < Self.previewConcurrency, let panel = pending.next() {
                group.addTask { await Self.fetchPreview(for: panel, connection: connection) }
                started += 1
            }
            while let result = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    continue
                }
                previews[result.0] = result.1
                if let next = pending.next() {
                    group.addTask { await Self.fetchPreview(for: next, connection: connection) }
                }
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
        previews = seeded
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
