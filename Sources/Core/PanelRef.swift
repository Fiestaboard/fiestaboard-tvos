import Foundation

/// The shape of a panel reference: a hub panel id or its short code.
///
/// Hub ids are `secrets.token_urlsafe(9)` (`[A-Za-z0-9_-]`, 12 chars); short
/// codes are integers; imported ids may be UUIDs. Anything else — a query,
/// a fragment, `..`, a slash, a percent sign, whitespace — never becomes a
/// request path or a remembered panel (A7b, #24 review S3). A deep link's
/// path is percent-decoded by `URL`, so `%3F` arrives here as `?`.
public enum PanelRef {
    public static let maxLength = 64
    private static let allowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    public static func isValid(_ ref: String) -> Bool {
        guard !ref.isEmpty, ref.count <= maxLength, ref != ".", ref != ".." else { return false }
        return ref.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// `ref` as one path segment, or nil if it isn't a valid reference.
    /// Valid references need no escaping; the encoding is belt and braces.
    public static func segment(_ ref: String) -> String? {
        guard isValid(ref) else { return nil }
        return ref.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}
