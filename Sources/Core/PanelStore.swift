import Foundation

public enum ConnectionState: Equatable, Sendable {
    case connecting
    case live
    /// The board is unreachable. The last frame stays up; only the corner
    /// indicator changes.
    case stale
    /// The board answered 401 and the stored credential could not put it
    /// right. Deliberately not `.stale`: the amber indicator means "still
    /// trying", and waiting does not fix a refused session — a person has to
    /// sign in. Polling on would only spend requests the board is certain to
    /// refuse.
    case unauthorized
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
    /// Burn-in drift, in points. `.zero` unless this TV asked for it.
    public let drift: BoardOffset
    /// What the board says, in the server's own words.
    ///
    /// The canvas is hidden from VoiceOver — 810 flaps are not browsable —
    /// so this is what the viewer's single accessibility element reads out.
    /// It was decoded off the wire and thrown away for as long as the app has
    /// existed.
    public let message: String?
    public let richCells: [[MatrixCell]]?

    /// Spelled out rather than synthesised so `drift` can default: it is a
    /// late arrival and every existing caller predates it. `message` is a
    /// later arrival still, and defaults for the same reason — appended
    /// rather than slotted in beside `cells`, so no existing call site has to
    /// reorder its arguments.
    public init(panel: Panel?, cells: [[BoardCell]], rows: Int, cols: Int,
                connection: ConnectionState, dimmed: Bool, deleted: Bool,
                drift: BoardOffset = .zero,
                message: String? = nil, richCells: [[MatrixCell]]? = nil) {
        self.panel = panel
        self.cells = cells
        self.rows = rows
        self.cols = cols
        self.connection = connection
        self.dimmed = dimmed
        self.deleted = deleted
        self.drift = drift
        self.message = message
        self.richCells = richCells
    }

    public static let empty = PanelSnapshot(panel: nil, cells: [], rows: 0, cols: 0,
                                            connection: .connecting, dimmed: false, deleted: false)

    /// Retained pixels are useful in an outage; retained words are not current.
    public var spokenContent: String {
        if deleted { return "Panel was removed." }
        if panel?.boardMissing == true { return "Board was removed." }
        switch connection {
        case .connecting: return "Connecting."
        case .stale: return "Disconnected. Showing the last frame."
        case .unauthorized: return "Sign in to view this panel."
        case .live: break
        }
        if let panel, panel.renderStyle == .ledMatrix {
            return MatrixRaster.make(panel: panel, cells: cells, richCells: richCells).spoken(message: message)
        }
        return BoardSpeech.spoken(message: message, cells: cells)
    }
}

/// Something that can run a request against the board with a session behind it.
///
/// `ConnectionStore.authorized` is the app's one place that spends a stored
/// credential on an expired session, and the viewer used to be the single
/// caller that went round it holding a bare client. So a wall-mounted board
/// that met one 401 — and the server caps a session at 30 days, so every
/// board meets one eventually — polled a refusal every two seconds until
/// somebody walked over to it with the remote.
///
/// Declared here next to its only consumer rather than in
/// `ConnectionStore.swift`: the conformance below is empty, Core owns both
/// types, and this way the store's own file did not have to be reopened.
public protocol AuthorizedRunner: Sendable {
    func authorized<T>(_ operation: (FiestaClient) async throws -> T) async throws -> T
}

extension ConnectionStore: AuthorizedRunner {}

/// A client with nothing in front of it, for callers that have no session to
/// manage: the tests, and a board with authentication switched off.
private struct DirectRunner: AuthorizedRunner {
    let client: FiestaClient

    func authorized<T>(_ operation: (FiestaClient) async throws -> T) async throws -> T {
        try await operation(client)
    }
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

    private let runner: AuthorizedRunner
    private let ref: String
    private let frameInterval: TimeInterval
    private let configInterval: TimeInterval
    private let clock: () -> Date
    private let signage: SignageSettings

    /// The poll loop, and the only mutable state left on the instance.
    ///
    /// Everything the loop carries between ticks is a local of `run(into:)`,
    /// and the stream's continuation is passed in as a parameter — both used
    /// to be stored properties written by the loop on the global executor
    /// while `stop()` wrote them from the main thread. A lock rather than an
    /// actor, because `stop()` is called from synchronous SwiftUI closures
    /// that cannot `await`.
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    public init(runner: AuthorizedRunner,
                ref: String,
                frameInterval: TimeInterval = PanelStore.frameIntervalDefault,
                configInterval: TimeInterval = PanelStore.configIntervalDefault,
                clock: @escaping () -> Date = Date.init,
                signage: SignageSettings = .shared) {
        self.runner = runner
        self.ref = ref
        self.frameInterval = frameInterval
        self.configInterval = configInterval
        self.clock = clock
        self.signage = signage
    }

    /// For a caller holding a bare client and no session to renew.
    public convenience init(client: FiestaClient,
                            ref: String,
                            frameInterval: TimeInterval = PanelStore.frameIntervalDefault,
                            configInterval: TimeInterval = PanelStore.configIntervalDefault,
                            clock: @escaping () -> Date = Date.init,
                            signage: SignageSettings = .shared) {
        self.init(runner: DirectRunner(client: client),
                  ref: ref,
                  frameInterval: frameInterval,
                  configInterval: configInterval,
                  clock: clock,
                  signage: signage)
    }

    public func snapshots() -> AsyncStream<PanelSnapshot> {
        // A second call must not leave the first loop polling the board with
        // nobody left to read it.
        stop()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in self?.stop() }
            // Weak, so the task does not keep the store alive: with a strong
            // capture `deinit` could never run and was dead code.
            let task = Task { [weak self] in
                await self?.run(into: continuation)
                // The loop ending ends the stream — whether it ended because
                // `stop()` cancelled it or because the store went away.
                continuation.finish()
            }
            lock.withLock { self.task = task }
        }
    }

    private func run(into continuation: AsyncStream<PanelSnapshot>.Continuation) async {
        let ref = self.ref
        var sinceConfig = configInterval  // fetch config on the first tick
        var connection = ConnectionState.connecting
        var deleted = false

        // Last good state — kept so an outage changes the indicator, not the
        // board. Locals, not properties: a cancelled loop that has not
        // noticed yet must not be able to scribble on its successor's.
        var panel: Panel?
        var cells: [[BoardCell]] = []
        var rows = 0
        var cols = 0
        var message: String?
        var richCells: [[MatrixCell]]?

        while !Task.isCancelled {
            if sinceConfig >= configInterval {
                sinceConfig = 0
                do {
                    panel = try await runner.authorized { try await $0.panel(ref: ref) }
                    deleted = false
                } catch FiestaError.notFound {
                    deleted = true
                    message = nil
                } catch FiestaError.unauthorized {
                    connection = .unauthorized
                } catch {
                    // A config miss is not fatal: the last one still describes
                    // the board well enough to keep drawing it.
                }
            }

            if !deleted {
                do {
                    let frame = try await runner.authorized { try await $0.frame(ref: ref) }
                    let glyph = panel?.effectiveCode62 ?? .degree
                    rows = frame.rows
                    cols = frame.cols
                    if let characters = frame.characters {
                        cells = BoardTables.cells(from: characters, code62: glyph)
                    } else {
                        cells = Array(repeating: Array(repeating: BoardCell.blank, count: max(cols, 0)),
                                      count: max(rows, 0))
                    }
                    message = frame.message
                    richCells = frame.richCells
                    connection = .live
                } catch FiestaError.notFound {
                    deleted = true
                    message = nil
                } catch FiestaError.unauthorized {
                    connection = .unauthorized
                    message = nil
                } catch {
                    connection = .stale
                    // The flaps keep their last frame, but the message is a
                    // claim about *now*: a dead board must stop speaking it.
                    message = nil
                }
                // Note what does NOT happen on a 401: `continue`. Skipping the
                // sleep below would turn one refused session into an
                // unthrottled request loop against a Raspberry Pi.
            }

            // This tick is also the drift's heartbeat: at a couple of
            // points a minute, a step every frame interval is far below
            // anything the eye resolves, so it needs no animation of its own.
            let now = clock()
            let dimmed = panel.map {
                AutoDimWindow.isDimmed($0.autoDim, at: now, override: signage.autoDimOverride)
            } ?? false
            continuation.yield(PanelSnapshot(panel: panel, cells: cells, rows: rows, cols: cols,
                                             connection: connection, dimmed: dimmed, deleted: deleted,
                                             drift: signage.drift(at: now),
                                             message: message, richCells: richCells))

            try? await Task.sleep(nanoseconds: UInt64(frameInterval * 1_000_000_000))
            sinceConfig += frameInterval
        }
    }

    public func stop() {
        // Taken out of the lock and cancelled outside it: cancelling can end
        // the loop, which finishes the stream, which calls `onTermination`,
        // which calls straight back into here.
        let running = lock.withLock { () -> Task<Void, Never>? in
            let running = task
            task = nil
            return running
        }
        running?.cancel()
    }

    deinit { task?.cancel() }
}
