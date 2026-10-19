#if DEBUG
import Foundation

/// A UI-review fixture that releases discovery only after the remote has
/// reached the control under test. Real LAN services cannot affect the run.
/// Available only in debug builds and only through an explicit launch arg.
final class ConnectReviewDiscovery: BoardDiscovering {
    private let endpoint: URL
    private var request: URLSessionDataTask?
    private var continuation: AsyncStream<[DiscoveredBoard]>.Continuation?

    private struct Board: Decodable {
        let id: String
        let name: String
        let host: URL
    }

    private init(endpoint: URL) { self.endpoint = endpoint }

    static func fromLaunchArguments() -> ConnectReviewDiscovery? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-fiestaboard.discoveryFixture"),
              index + 1 < arguments.count,
              let endpoint = URL(string: arguments[index + 1]),
              endpoint.scheme == "http", endpoint.host == "127.0.0.1" else { return nil }
        return ConnectReviewDiscovery(endpoint: endpoint)
    }

    func boards() -> AsyncStream<[DiscoveredBoard]> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield([])
            request = URLSession.shared.dataTask(with: endpoint) { data, _, _ in
                guard let data,
                      let boards = try? JSONDecoder().decode([Board].self, from: data) else { return }
                continuation.yield(boards.map {
                    DiscoveredBoard(id: $0.id, name: $0.name, host: $0.host)
                })
                // Keep browsing until stop(), just like BonjourDiscovery.
            }
            request?.resume()
        }
    }

    func stop() {
        request?.cancel()
        request = nil
        continuation?.finish()
        continuation = nil
    }
}
#endif
