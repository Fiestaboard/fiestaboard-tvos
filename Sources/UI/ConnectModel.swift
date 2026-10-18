import Foundation
import Observation

@MainActor
@Observable
final class ConnectModel {

    var boards: [DiscoveredBoard] = []

    /// What the browse is doing, as one value.
    ///
    /// It replaced a pair of independent booleans — "is scanning" and "has
    /// looked long enough" — because a freshly built model had both false,
    /// and the screen read that pair as the terminal "nothing on this
    /// network" state and painted it before a packet had gone out. One
    /// property leaves no combination to misread.
    enum ScanState: Equatable {
        /// No browse is running: before the first `startScan`, and after any
        /// teardown. On screen this is always the moment before a scan
        /// starts — `.onAppear`'s task is a hop behind the model, and every
        /// `stopScan` either leaves this screen or is `rescan`'s first half —
        /// so it is patient rather than a verdict.
        case idle

        /// A browse is running and has not yet earned the right to say the
        /// network is empty.
        ///
        /// Nothing fakes this to end the "looking…" copy early: it is the
        /// liveness record too, and clearing it would let `.onAppear` start a
        /// second `NWBrowser` over a browse that is still very much alive.
        case looking

        /// Listened long enough to say "nothing here yet" without lying about
        /// it. The browse is *still running* — a board powered on at second
        /// 20 still lands in the list and puts this back to `.looking`.
        case foundNothing

        /// Whether the screen may still promise a board is coming.
        ///
        /// Deliberately not "is a browse running": the browse outlives the
        /// promise, which is the whole reason `.foundNothing` exists. It
        /// lives here rather than in `ConnectScreen`'s body because that is
        /// where nothing could reach it.
        var promisesABoardIsComing: Bool {
            switch self {
            case .idle, .looking: return true
            case .foundNothing:   return false
            }
        }
    }

    private(set) var scanState: ScanState = .idle

    var manualAddress = ""
    var errorMessage: String?
    private(set) var isConnecting = false

    /// Which board is mid-connect, by `DiscoveredBoard.id`. `authStatus()`
    /// then `login()` is two ten-second timeouts back to back, so without
    /// this the screen sits completely unchanged for twenty seconds after a
    /// press and reads as broken.
    private(set) var connectingBoardID: String?

    /// Whether the card for `boardID` is the one holding the press.
    ///
    /// The comparison lives here rather than in `ConnectScreen`'s body
    /// because that is where nothing could reach it: the suite could only
    /// assert that the marker gets *cleared*, which is the half that was
    /// never broken.
    func connectInFlight(for boardID: String) -> Bool {
        connectingBoardID == boardID
    }

    /// Whether the in-flight connect belongs to the typed address rather
    /// than to one of the cards — the cards show their own spinner, and two
    /// at once would claim two attempts are running.
    var manualConnectInFlight: Bool {
        guard let connectingBoardID else { return false }
        return !boards.contains { $0.id == connectingBoardID }
    }

    /// How long the screen waits before admitting it has found nothing.
    /// Injectable so tests do not have to wait it out.
    ///
    /// `nonisolated` because it is read from the default argument of
    /// `startScan`, which is evaluated at the call site outside this class's
    /// actor — main-actor isolation there is a warning today and a hard error
    /// under the Swift 6 language mode.
    nonisolated static let defaultPatience: Duration = .seconds(12)

    private let app: AppModel
    private var discovery: BoardDiscovering?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var patienceTask: Task<Void, Never>?
    /// Bumped per scan, so a scan that was torn down mid-`await` can tell it
    /// is no longer the current one before it clears anybody's state.
    @ObservationIgnored private var scanGeneration = 0

    init(app: AppModel) { self.app = app }

    func startScan(using discovery: BoardDiscovering = BonjourDiscovery(),
                   patience: Duration = ConnectModel.defaultPatience) async {
        // One browse at a time. Bonjour's stream only ends when `stop()` ends
        // it, so a second `startScan` would leave two browsers running and
        // only ever stop the newer one. The rejected discovery is stopped
        // here because nothing else holds it: the default argument builds a
        // fresh one at every call site.
        guard scanTask == nil else {
            discovery.stop()
            return
        }
        // And if a discovery is somehow still here, stop it before dropping
        // the reference — otherwise its browser outlives the app's ability to
        // reach it.
        self.discovery?.stop()
        self.discovery = discovery

        scanGeneration += 1
        let generation = scanGeneration
        scanState = .looking

        // Not a timeout: nothing below is cancelled when this fires. It only
        // earns the screen the right to stop saying "this takes a few
        // seconds" to someone whose board is switched off.
        patienceTask = Task { [weak self] in
            try? await Task.sleep(for: patience)
            guard let self, !Task.isCancelled else { return }
            if self.boards.isEmpty { self.scanState = .foundNothing }
        }

        let task = Task { [weak self] in
            for await found in discovery.boards() {
                guard let self else { return }
                self.boards = found
                // A board that arrives after the window puts the screen back
                // into the state where it has something to show.
                if !found.isEmpty { self.scanState = .looking }
            }
        }
        scanTask = task
        await task.value

        // `stopScan()` during that await has already torn this scan down, and
        // may have started another one behind it. Only the current scan is
        // allowed to put the screen back to `.idle`.
        guard generation == scanGeneration else { return }
        patienceTask?.cancel()
        patienceTask = nil
        scanTask = nil
        scanState = .idle
    }

    func stopScan() {
        patienceTask?.cancel()
        patienceTask = nil
        scanTask?.cancel()
        scanTask = nil
        discovery?.stop()
        discovery = nil
        scanState = .idle
    }

    /// "Search again": a clean browse with the patience window restarted.
    func rescan(using discovery: BoardDiscovering = BonjourDiscovery(),
                patience: Duration = ConnectModel.defaultPatience) async {
        stopScan()
        await startScan(using: discovery, patience: patience)
    }

    func connect(to host: URL, name: String) async {
        guard !isConnecting else { return }
        isConnecting = true
        connectingBoardID = host.absoluteString
        errorMessage = nil
        // The app-level message outlives the attempt that produced it. One
        // board that needed setup used to make every later failure read "no
        // account yet" for a board that was simply switched off.
        app.errorMessage = nil
        defer {
            isConnecting = false
            connectingBoardID = nil
        }
        do {
            let previousHost = app.connection.saved?.host
            let result = try await app.connection.connect(to: host, displayName: name)
            if previousHost != host { app.clearTopShelf() }
            // `.needsSetup` routes to `.connect` — the screen already on
            // screen — so `.onAppear` never fires again. Stopping discovery
            // on that path left the app with no browser for the rest of its
            // life, and nothing to show but the address field.
            if result != .needsSetup { stopScan() }
            app.finishConnect(result)
            // That path succeeds at the wire and still leaves a message on
            // screen; the banner is not focusable, so VoiceOver hears nothing
            // unless it is said out loud.
            if let message = app.errorMessage { Announce.say(message) }
        } catch FiestaError.transport {
            // Nothing answered at all — the one failure that really is the
            // network. `FiestaError.userMessage` is written for screens that
            // already know which board they are on and says "your
            // FiestaBoard"; here the person has just typed or chosen an
            // address and has no idea which one the app tried. This used to
            // fall to the `catch let error as FiestaError` arm below, so the
            // address-naming line was unreachable.
            fail(with: Self.unreachable(host))
        } catch let error as FiestaError {
            // A board that answered 409, 429 or 500 is not an unreachable
            // board. `userMessage` is where that judgement already lives —
            // blaming the network sends people to check cables while the
            // board sits there replying.
            fail(with: error.userMessage)
        } catch {
            fail(with: Self.unreachable(host))
        }
    }

    func connectManually() async {
        errorMessage = nil
        app.errorMessage = nil
        guard let url = ManualAddress.parse(manualAddress) else {
            fail(with: "Enter an address like 192.168.1.50, board.local, or https://your-board.example.com")
            return
        }
        await connect(to: url, name: url.host() ?? "FiestaBoard")
    }

    private static func unreachable(_ host: URL) -> String {
        "Couldn't reach \(host.host() ?? host.absoluteString). Check it's on and on this network."
    }

    /// Record the failure and say it out loud — see
    /// `Announce.say(_:recordingIn:)`.
    private func fail(with message: String) {
        Announce.say(message, recordingIn: &errorMessage)
    }
}
