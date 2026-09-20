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
    /// separates it from every other HTTP service on the network; the service
    /// name is a fallback for instances too old to publish TXT.
    public static func isFiestaBoard(_ candidate: DiscoveryCandidate) -> Bool {
        for (key, value) in candidate.txt where key.lowercased() == productKey {
            if value.lowercased() == productValue { return true }
        }
        return candidate.name.lowercased().hasPrefix(productValue)
    }

    public static func url(for candidate: DiscoveryCandidate) -> URL? {
        var host = candidate.host
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return nil }

        // A bare Bonjour hostname resolves only with the .local suffix.
        let isIPv4 = host.allSatisfy { $0.isNumber || $0 == "." }
        let isIPv6 = host.contains(":")
        if !host.contains("."), !isIPv6 {
            host += ".local"
        }
        if isIPv6 { host = "[\(host)]" }
        _ = isIPv4

        let authority = candidate.port == 80 ? host : "\(host):\(candidate.port)"
        return URL(string: "http://\(authority)")
    }
}

/// Parses whatever someone managed to type on a Siri Remote.
public enum ManualAddress {

    public static func parse(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }

        if text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") {
            return URL(string: text)
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
