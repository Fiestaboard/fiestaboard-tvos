import Foundation

/// A FiestaBoard found on the network, ready to connect to.
public struct DiscoveredBoard: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let host: URL

    public init(id: String, name: String, host: URL) {
        self.id = id
        self.name = name
        self.host = host
    }
}

/// A Bonjour service before we have decided whether it is ours.
public struct DiscoveryCandidate: Equatable, Sendable {
    public let name: String
    public let host: String
    public let port: Int
    public let txt: [String: String]

    public init(name: String, host: String, port: Int, txt: [String: String]) {
        self.name = name
        self.host = host
        self.port = port
        self.txt = txt
    }
}

/// Source of discovered boards. A protocol so the UI can be driven by a
/// fixed list in tests and previews, and so the Android port has an obvious
/// seam (`NsdManager`).
public protocol BoardDiscovering: AnyObject {
    func boards() -> AsyncStream<[DiscoveredBoard]>
    func stop()
}

public enum DiscoveryFilter {

    public static let defaultPort = 4420
    private static let productKey = "product"
    private static let productValue = "fiestaboard"

    /// FiestaBoard advertises `_http._tcp` with `product=FiestaBoard` in TXT.
    /// Until a dedicated `_fiestaboard._tcp` type exists, that record is what
    /// separates it from every other HTTP service on the network.
    ///
    /// The service name is a fallback, and only for a service publishing *no*
    /// TXT at all — the legacy FiestaPi images. Accepting a bare name from
    /// anything that does publish TXT let any host on the LAN offer itself as
    /// a board by picking its name, and every shipping advertiser (the Pi
    /// image's Avahi file and the server's own zeroconf registration) sends
    /// `product=FiestaBoard`, so nothing real depends on the loose path.
    public static func isFiestaBoard(_ candidate: DiscoveryCandidate) -> Bool {
        for (key, value) in candidate.txt where key.lowercased() == productKey {
            if value.lowercased() == productValue { return true }
        }
        guard candidate.txt.isEmpty else { return false }
        return candidate.name.lowercased().hasPrefix(productValue)
    }

    public static func url(for candidate: DiscoveryCandidate) -> URL? {
        var host = candidate.host
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return nil }

        // A bare Bonjour hostname resolves only with the .local suffix.
        let isIPv6 = host.contains(":")
        if !host.contains("."), !isIPv6 {
            host += ".local"
        }
        if isIPv6 { host = "[\(host)]" }

        let authority = candidate.port == 80 ? host : "\(host):\(candidate.port)"
        return URL(string: "http://\(authority)")
    }
}

/// Parses whatever someone managed to type on a Siri Remote.
public enum ManualAddress {

    public static func parse(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Decide this before trimming: "http://" trims down to "http:", which
        // would otherwise be mistaken for a hostname with a port.
        let lowered = text.lowercased()
        let hasScheme = lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }

        if hasScheme {
            guard var components = URLComponents(string: text),
                  !(components.host ?? "").isEmpty else { return nil }
            // A browser address bar gives "http://192.168.0.50", which URL
            // reads as port 80 — the board answers on 4420, so the connect
            // failed with "couldn't reach", blaming the network for a port
            // the user was never asked for. Only the bare http host gets the
            // default: an https URL, an explicit port, or a reverse-proxy
            // subpath all mean the address says what it means.
            if components.scheme?.lowercased() == "http",
               components.port == nil,
               components.path.isEmpty {
                components.port = DiscoveryFilter.defaultPort
            }
            return components.url
        }

        // No scheme. Add the default port unless one was typed, so the
        // common case is four numbers and nothing else.
        let hasPort = text.split(separator: "/").first.map { $0.contains(":") } ?? false
        let hasPath = text.contains("/")
        if hasPort || hasPath {
            return URL(string: "http://\(text)")
        }
        return URL(string: "http://\(text):\(DiscoveryFilter.defaultPort)")
    }
}
