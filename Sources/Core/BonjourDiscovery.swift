import Foundation
import Network

/// Browses `_http._tcp` and keeps the services that look like a FiestaBoard,
/// confirming each with a real request before offering it.
///
/// The confirmation matters: TXT records are advertised, not proven, and a
/// list that offers an unreachable board is worse than a short list.
///
/// `@unchecked Sendable` rests entirely on one rule: every stored mutable
/// field is read and written on `queue` and nowhere else. `NWBrowser` and
/// `NWConnection` deliver their callbacks there because they are started with
/// it, and everything that reaches this object from outside — `boards()`,
/// `stop()`, the probe's `Task` — hops onto it first. Touching `browser`,
/// `connections`, `found`, `resolved` or `continuation` from anywhere else
/// silently voids the conformance.
public final class BonjourDiscovery: BoardDiscovering, @unchecked Sendable {

    /// Existing FiestaPi images publish this hostname through host Avahi.
    private static let legacyFiestaPiURL = URL(string: "http://fiestapi.local:\(DiscoveryFilter.defaultPort)")!
    /// The service name a FiestaPi announces once it is new enough to.
    private static let legacyFiestaPiServiceName = "FiestaBoard on fiestapi"
    /// How long to wait for service browsing before falling back to it.
    private static let legacyProbeDelay: TimeInterval = 1
    /// How long a resolve connection may sit short of `.ready` before we give
    /// up on it. Bonjour will happily advertise a service reachable only on an
    /// interface this Apple TV has no route to; such a connection sits in
    /// `.waiting` indefinitely and used to hold its slot until `stop()`.
    private static let resolveTimeout: TimeInterval = 3
    /// How long to wait before going back to a candidate that resolved but
    /// did not confirm, and the ceiling the doubling stops at.
    static let retryDelay: TimeInterval = 2
    private static let retryCeiling: TimeInterval = 30

    private let queue = DispatchQueue(label: "com.fiestaboard.tv.discovery")
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private var found: [String: DiscoveredBoard] = [:]
    /// Endpoints a resolve is in flight for, or that have already confirmed.
    ///
    /// Two opposed pressures meet in this one set, and whoever next touches it
    /// will arrive holding only one of them.
    ///
    /// It exists because `browseResultsChangedHandler` hands us the whole
    /// result set on every churn event, not the delta: without a gate, one new
    /// service appearing re-resolved and re-probed every board already on
    /// screen.
    ///
    /// It must nevertheless be cleared by every path that drops a candidate,
    /// because the commonest reason to drop one is a board that is merely
    /// still booting — mDNS is up from the first second while nginx answers
    /// 503 for the next thirty to sixty, which is the case `FiestaError`
    /// spells "still starting up" and the Connect screen answers by promising
    /// the Apple TV is still listening. A stranded endpoint is skipped for the
    /// entire life of the browse, so that promise becomes a lie.
    ///
    /// Clearing alone is not enough either: the handler only fires when the
    /// advertised set *changes*, and a booting board changes nothing. So the
    /// probe path also comes back on its own — see `retry(_:url:name:)`.
    private var resolved: Set<NWEndpoint> = []
    /// What a later attempt at a dropped candidate needs, by endpoint. Pruned
    /// to what is still advertised on every browse callback.
    private var attempts: [NWEndpoint: Attempt] = [:]
    private var continuation: AsyncStream<[DiscoveredBoard]>.Continuation?

    /// A candidate that resolved to a real address and then failed to confirm.
    private struct Attempt {
        let url: URL
        let name: String
        /// Consecutive failures, which is what the backoff is measured in.
        var failures = 0
    }

    /// Confirms a candidate host is really a FiestaBoard. Injectable so tests
    /// and previews can skip the network.
    private let probe: @Sendable (URL) async -> Bool
    private let browseServices: Bool

    public init(probe: (@Sendable (URL) async -> Bool)? = nil,
                browseServices: Bool = true) {
        self.probe = probe ?? { url in
            // /auth/status is public on every instance and cheap.
            (try? await FiestaClient(baseURL: url, session: Self.sharedProbeSession).authStatus()) != nil
        }
        self.browseServices = browseServices
    }

    // MARK: The probe session

    /// The probe must be anonymous, and that is not a preference.
    ///
    /// The shared probe session must neither send nor accept cookies from
    /// discovered hosts. Cookies are scoped by domain and path, never port;
    /// another service on the host must not receive a board session.
    /// `/auth/status` is public, so anonymous discovery costs nothing.
    static func probeConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 5
        return config
    }

    static func probeSession() -> URLSession {
        URLSession(configuration: probeConfiguration())
    }

    /// One session for every probe on every instance. A session per candidate
    /// would leak one per service per scan, and sharing is safe precisely
    /// because `probeConfiguration()` leaves nothing to share.
    private static let sharedProbeSession = probeSession()

    // MARK: Browsing

    public func boards() -> AsyncStream<[DiscoveredBoard]> {
        AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in self?.stop() }
            self.queue.async {
                // A second boards() on the same instance must not orphan the
                // first stream or its browser — but detach the old termination
                // handler before finishing, or the finish re-enters stop() and
                // tears down the browse we are about to start.
                if let previous = self.continuation {
                    previous.onTermination = nil
                    previous.finish()
                }
                self.continuation = continuation
                self.startBrowsing()
            }
        }
    }

    /// Queue-confined. Called only from `boards()`.
    private func startBrowsing() {
        teardownBrowsing()
        guard browseServices else {
            probeLegacyFiestaPi()
            return
        }
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_http._tcp", domain: nil),
                                using: parameters)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            // A browser that has failed never recovers and never stops
            // retrying on its own; the legacy hostname probe is still worth
            // running, so drop the browser without ending the stream.
            if case .failed = state {
                self.browser?.cancel()
                self.browser = nil
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            // A service that went away and came back should be resolvable
            // again, so forget anything no longer being advertised — including
            // any retry it had queued.
            let live = Set(results.map(\.endpoint))
            self.resolved.formIntersection(live)
            self.attempts = self.attempts.filter { live.contains($0.key) }

            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                guard !self.resolved.contains(result.endpoint) else { continue }
                var txt: [String: String] = [:]
                if case let .bonjour(record) = result.metadata {
                    for (key, value) in record.dictionary { txt[key] = value }
                }
                let candidate = DiscoveryCandidate(name: name,
                                                   host: name,
                                                   port: DiscoveryFilter.defaultPort,
                                                   txt: txt)
                guard DiscoveryFilter.isFiestaBoard(candidate) else { continue }
                self.resolved.insert(result.endpoint)
                self.resolve(result.endpoint, name: name, txt: txt)
            }
        }

        browser.start(queue: queue)
        probeLegacyFiestaPi()
    }

    /// Existing FiestaPi images publish fiestapi.local through host Avahi but
    /// do not publish an HTTP service from their bridge container. Check that
    /// known hostname when service browsing has not found a FiestaBoard.
    private func probeLegacyFiestaPi() {
        queue.asyncAfter(deadline: .now() + Self.legacyProbeDelay) { [weak self] in
            guard let self, self.continuation != nil, self.found.isEmpty else { return }
            Task {
                await self.confirm(url: Self.legacyFiestaPiURL, name: "FiestaPi",
                                   onlyIfEmpty: true)
            }
        }
    }

    /// Bonjour gives a service endpoint; a URL needs a hostname and port, so
    /// open a connection far enough to read the resolved path, then drop it.
    private func resolve(_ endpoint: NWEndpoint, name: String, txt: [String: String]) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        queue.async { self.connections.append(connection) }

        // `connection` is weak here on purpose: the connection owns its state
        // handler, the handler owns this work item, and a strong capture would
        // close that loop and keep every timed-out resolve alive for the life
        // of the process.
        let deadline = DispatchWorkItem { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.resolved.remove(endpoint)
            self.discard(connection)
        }
        queue.asyncAfter(deadline: .now() + Self.resolveTimeout, execute: deadline)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                deadline.cancel()
                guard let path = connection.currentPath,
                      let remote = path.remoteEndpoint,
                      case let .hostPort(host, port) = remote else {
                    // Eligible again, but there is no address to come back to
                    // on our own, so this one waits for the next churn event.
                    self.resolved.remove(endpoint)
                    self.discard(connection)
                    return
                }
                let hostString = Self.hostString(from: host)
                self.discard(connection)

                let candidate = DiscoveryCandidate(name: name,
                                                   host: hostString,
                                                   port: Int(port.rawValue),
                                                   txt: txt)
                // The one drop that stays gated on purpose: `url(for:)` only
                // fails on a host string that cannot become a URL, and the
                // next resolve of the same endpoint would produce the same
                // one. Forgetting it here would re-resolve it on every churn
                // event for nothing.
                guard let url = DiscoveryFilter.url(for: candidate) else { return }
                Task { await self.confirm(url: url, name: name, endpoint: endpoint) }

            case .failed:
                // Only .failed forgets the endpoint. .cancelled is always our
                // own doing — the success path above, the deadline, or stop()
                // — and forgetting there would re-resolve a board we just
                // resolved on the very next browse callback. A connection
                // that never reached .ready has no address to re-probe, so
                // like the deadline it settles for being eligible again.
                deadline.cancel()
                self.resolved.remove(endpoint)
                self.discard(connection)
            case .cancelled:
                deadline.cancel()
                self.discard(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// Cancel a resolve connection and stop tracking it. A browse that runs
    /// while someone reads the Connect screen can resolve the same service
    /// repeatedly; without this the array only ever grew.
    private func discard(_ connection: NWConnection) {
        connection.cancel()
        queue.async {
            self.connections.removeAll { $0 === connection }
        }
    }

    /// Keep the interface suffix on link-local IPv6 addresses. Without it,
    /// the URL probe has no route even though Bonjour resolved the service.
    static func hostString(from host: NWEndpoint.Host) -> String {
        switch host {
        case .name(let name, _): return name
        case .ipv4(let address): return "\(address)"
        case .ipv6(let address): return "\(address)"
        @unknown default: return "\(host)"
        }
    }

    /// - Parameter endpoint: the Bonjour endpoint this URL came from, when it
    ///   came from one. Without it a candidate that fails the probe is dropped
    ///   silently and its endpoint is stranded in `resolved` for the life of
    ///   the browse; the legacy hostname probe is the only caller with nothing
    ///   to pass.
    func confirm(url: URL, name: String, endpoint: NWEndpoint? = nil,
                 onlyIfEmpty: Bool = false) async {
        guard await probe(url) else {
            if let endpoint {
                queue.async { self.retry(endpoint, url: url, name: name) }
            }
            return
        }
        queue.async {
            guard self.continuation != nil else { return }
            if let endpoint { self.attempts.removeValue(forKey: endpoint) }
            if onlyIfEmpty && !self.found.isEmpty { return }
            // A newly updated FiestaPi may announce its service after the
            // hostname fallback appeared. Replace that fallback entry.
            if name.caseInsensitiveCompare(Self.legacyFiestaPiServiceName) == .orderedSame {
                self.found.removeValue(forKey: Self.legacyFiestaPiURL.absoluteString)
            }
            let board = DiscoveredBoard(id: url.absoluteString, name: name, host: url)
            guard self.found[board.id] != board else { return }
            self.found[board.id] = board
            let sorted = self.found.values.sorted { $0.name < $1.name }
            self.continuation?.yield(sorted)
        }
    }

    /// A board whose service is advertised but whose HTTP server is not
    /// serving yet: let the browse have it back, and come back to it.
    ///
    /// Both halves are load-bearing. Taking it out of `resolved` is what lets
    /// a later churn event resolve it again from scratch, in case it comes
    /// back at another address. Re-probing on a timer is what covers the case
    /// where no churn event ever comes, which is the usual one — a board
    /// finishing its boot changes nothing that Bonjour reports.
    ///
    /// The delay doubles to a ceiling so the second half cannot become the
    /// churn the first half exists to prevent: a host that is never coming
    /// back costs one probe every `retryCeiling` seconds, and a board that
    /// takes a minute to serve is still picked up within one. There is no
    /// attempt limit on purpose — the browse runs for as long as the Connect
    /// screen is open, and giving up would put back the bug this fixes.
    ///
    /// Queue-confined.
    private func retry(_ endpoint: NWEndpoint, url: URL, name: String) {
        resolved.remove(endpoint)
        guard continuation != nil else { return }
        let failures = (attempts[endpoint]?.failures ?? 0) + 1
        attempts[endpoint] = Attempt(url: url, name: name, failures: failures)
        let delay = min(Self.retryCeiling,
                        Self.retryDelay * pow(2.0, Double(failures - 1)))
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.continuation != nil,
                  let attempt = self.attempts[endpoint],
                  // A browse callback may have resolved it in the meantime;
                  // that attempt supersedes this one.
                  !self.resolved.contains(endpoint) else { return }
            self.resolved.insert(endpoint)
            Task { await self.confirm(url: attempt.url, name: attempt.name, endpoint: endpoint) }
        }
    }

    public func stop() {
        queue.async {
            self.teardownBrowsing()
            self.continuation?.finish()
            self.continuation = nil
        }
    }

    /// Everything a live browse holds, released. Queue-confined, and safe to
    /// run twice: `stop()` finishes the stream, whose `onTermination` calls
    /// `stop()` straight back.
    private func teardownBrowsing() {
        browser?.cancel()
        browser = nil
        connections.forEach { $0.cancel() }
        connections = []
        resolved = []
        attempts = [:]
        found = [:]
    }
}
