import Foundation

public enum ConnectionState: Equatable, Sendable {
    case connecting
    case live
    /// The board is unreachable. The last frame stays up; only the corner
    /// indicator changes.
    case stale
}

/// Everything the viewer needs to draw, in one value.
public struct PanelSnapshot: Sendable {
    public let panel: Panel?
    public let cells: [[BoardCell]]
    public let rows: Int
    public let cols: Int
    public let connection: ConnectionState
    public let dimmed: Bool
    /// The panel was deleted in the app; there is nothing to come back to.
    public let deleted: Bool

    public static let empty = PanelSnapshot(panel: nil, cells: [], rows: 0, cols: 0,
                                            connection: .connecting, dimmed: false, deleted: false)
}

/// Polls a panel and publishes snapshots.
///
/// Two cadences, matching the web viewer: frames every 2s because they are
/// the display, config every 10s because edits made in the app should reach
/// a wall-mounted TV without anyone walking over to it.
///
/// There is no retry inside a tick. The cadence IS the retry policy —
/// retrying inside a 2-second loop only multiplies requests during an
/// outage, which is exactly when the board is least able to answer.
public final class PanelStore: @unchecked Sendable {

    public static let frameIntervalDefault: TimeInterval = 2.0
    public static let configIntervalDefault: TimeInterval = 10.0

    private let client: FiestaClient
    private let ref: String
    private let frameInterval: TimeInterval
    private let configInterval: TimeInterval
    private let clock: () -> Date

    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<PanelSnapshot>.Continuation?

    // Last good state — kept so an outage changes the indicator, not the board.
    private var panel: Panel?
    private var cells: [[BoardCell]] = []
    private var rows = 0
    private var cols = 0

    public init(client: FiestaClient,
                ref: String,
                frameInterval: TimeInterval = PanelStore.frameIntervalDefault,
                configInterval: TimeInterval = PanelStore.configIntervalDefault,
                clock: @escaping () -> Date = Date.init) {
        self.client = client
        self.ref = ref
        self.frameInterval = frameInterval
        self.configInterval = configInterval
        self.clock = clock
    }

    public func snapshots() -> AsyncStream<PanelSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in self?.stop() }
            self.task = Task { await self.run() }
        }
    }

    private func run() async {
        var sinceConfig = configInterval  // fetch config on the first tick
        var connection = ConnectionState.connecting
        var deleted = false

        while !Task.isCancelled {
            if sinceConfig >= configInterval {
                sinceConfig = 0
                do {
                    panel = try await client.panel(ref: ref)
                    deleted = false
                } catch FiestaError.notFound {
                    deleted = true
                } catch {
                    // A config miss is not fatal: the last one still describes
                    // the board well enough to keep drawing it.
                }
            }

            if !deleted {
                do {
                    let frame = try await client.frame(ref: ref)
                    let glyph = panel?.effectiveCode62 ?? .degree
                    rows = frame.rows
                    cols = frame.cols
                    if let characters = frame.characters {
                        cells = BoardTables.cells(from: characters, code62: glyph)
                    } else {
                        cells = Array(repeating: Array(repeating: BoardCell.blank, count: max(cols, 0)),
                                      count: max(rows, 0))
                    }
                    connection = .live
                } catch FiestaError.notFound {
                    deleted = true
                } catch {
                    connection = .stale
                }
            }

            let dimmed = panel.map { AutoDimWindow.isDimmed($0.autoDim, at: clock()) } ?? false
            continuation?.yield(PanelSnapshot(panel: panel, cells: cells, rows: rows, cols: cols,
                                              connection: connection, dimmed: dimmed, deleted: deleted))

            try? await Task.sleep(nanoseconds: UInt64(frameInterval * 1_000_000_000))
            sinceConfig += frameInterval
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        continuation?.finish()
        continuation = nil
    }

    deinit { task?.cancel() }
}
