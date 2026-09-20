import Foundation
import Network

/// Browses `_http._tcp` and keeps the services that look like a FiestaBoard,
/// confirming each with a real request before offering it.
///
/// The confirmation matters: TXT records are advertised, not proven, and a
/// list that offers an unreachable board is worse than a short list.
public final class BonjourDiscovery: BoardDiscovering, @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.fiestaboard.tv.discovery")
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private var found: [String: DiscoveredBoard] = [:]
    private var continuation: AsyncStream<[DiscoveredBoard]>.Continuation?

    /// Confirms a candidate host is really a FiestaBoard. Injectable so tests
    /// and previews can skip the network.
    private let probe: @Sendable (URL) async -> Bool

    public init(probe: (@Sendable (URL) async -> Bool)? = nil) {
        self.probe = probe ?? { url in
            // /auth/status is public on every instance and cheap.
            (try? await FiestaClient(baseURL: url).authStatus()) != nil
        }
    }

    public func boards() -> AsyncStream<[DiscoveredBoard]> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in self?.stop() }
            self.startBrowsing()
        }
    }

    private func startBrowsing() {
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
                    connection.cancel()
                    return
                }
                let hostString: String
                switch host {
                case .name(let n, _): hostString = n
                case .ipv4(let address): hostString = "\(address)".components(separatedBy: "%").first ?? "\(address)"
                case .ipv6(let address): hostString = "\(address)".components(separatedBy: "%").first ?? "\(address)"
                @unknown default: hostString = name
                }
                connection.cancel()

                let candidate = DiscoveryCandidate(name: name,
                                                   host: hostString,
                                                   port: Int(port.rawValue),
                                                   txt: txt)
                guard let url = DiscoveryFilter.url(for: candidate) else { return }
                Task { await self.confirm(url: url, name: name) }

            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func confirm(url: URL, name: String) async {
        guard await probe(url) else { return }
        queue.async {
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
