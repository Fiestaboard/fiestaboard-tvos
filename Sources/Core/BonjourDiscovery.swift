import Foundation
import Network

/// Browses `_http._tcp` and keeps the services that look like a FiestaBoard,
/// confirming each with a real request before offering it.
///
/// The confirmation matters: TXT records are advertised, not proven, and a
/// list that offers an unreachable board is worse than a short list.
public final class BonjourDiscovery: BoardDiscovering, @unchecked Sendable {

    /// Existing FiestaPi images publish this hostname through host Avahi.
    private static let legacyFiestaPiURL = URL(string: "http://fiestapi.local:\(DiscoveryFilter.defaultPort)")!
    /// The service name a FiestaPi announces once it is new enough to.
    private static let legacyFiestaPiServiceName = "FiestaBoard on fiestapi"
    /// How long to wait for service browsing before falling back to it.
    private static let legacyProbeDelay: TimeInterval = 1

    private let queue = DispatchQueue(label: "com.fiestaboard.tv.discovery")
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private var found: [String: DiscoveredBoard] = [:]
    private var continuation: AsyncStream<[DiscoveredBoard]>.Continuation?

    /// Confirms a candidate host is really a FiestaBoard. Injectable so tests
    /// and previews can skip the network.
    private let probe: @Sendable (URL) async -> Bool
    private let browseServices: Bool

    public init(probe: (@Sendable (URL) async -> Bool)? = nil,
                browseServices: Bool = true) {
        self.probe = probe ?? { url in
            // /auth/status is public on every instance and cheap.
            (try? await FiestaClient(baseURL: url).authStatus()) != nil
        }
        self.browseServices = browseServices
    }

    public func boards() -> AsyncStream<[DiscoveredBoard]> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in self?.stop() }
            self.startBrowsing()
        }
    }

    private func startBrowsing() {
        guard browseServices else {
            probeLegacyFiestaPi()
            return
        }
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_http._tcp", domain: nil),
                                using: parameters)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                var txt: [String: String] = [:]
                if case let .bonjour(record) = result.metadata {
                    for (key, value) in record.dictionary { txt[key] = value }
                }
                let candidate = DiscoveryCandidate(name: name,
                                                   host: name,
                                                   port: DiscoveryFilter.defaultPort,
                                                   txt: txt)
                guard DiscoveryFilter.isFiestaBoard(candidate) else { continue }
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

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let path = connection.currentPath,
                      let remote = path.remoteEndpoint,
                      case let .hostPort(host, port) = remote else {
                    self.discard(connection)
                    return
                }
                let hostString = Self.hostString(from: host)
                self.discard(connection)

                let candidate = DiscoveryCandidate(name: name,
                                                   host: hostString,
                                                   port: Int(port.rawValue),
                                                   txt: txt)
                guard let url = DiscoveryFilter.url(for: candidate) else { return }
                Task { await self.confirm(url: url, name: name) }

            case .failed, .cancelled:
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

    private func confirm(url: URL, name: String, onlyIfEmpty: Bool = false) async {
        guard await probe(url) else { return }
        queue.async {
            guard self.continuation != nil else { return }
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

    public func stop() {
        queue.async {
            self.browser?.cancel()
            self.browser = nil
            self.connections.forEach { $0.cancel() }
            self.connections = []
            self.continuation?.finish()
            self.continuation = nil
        }
    }
}
