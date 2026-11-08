import Foundation

/// What this TV calls itself to the hub (PHASE-4-TV-PLAN A3, fact 10, DD3).
public enum DeviceNameChoice: Equatable, Sendable {
    /// The user-assigned Apple TV name ("Living Room").
    case assigned(String)
    /// No user-assigned name is available: tvOS returns the model name when
    /// the app lacks the user-assigned-device-name entitlement (O6), and a
    /// name equal to the model says nothing either. Sends "Apple TV".
    case fallback

    public var sent: String {
        if case .assigned(let name) = self { return name }
        return DeviceName.fallback
    }
}

public enum DeviceName {
    public static let fallback = "Apple TV"
    /// The hub accepts 1–100 characters (`src/auth/device_models.py`).
    public static let maxLength = 100

    /// No control characters, whitespace collapsed and trimmed, at most 100
    /// characters. Replaces the old `prefix(80)`, which cut names the hub
    /// would accept.
    public static func sanitize(_ raw: String) -> String {
        let spaced = String(String.UnicodeScalarView(raw.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : $0
        }))
        let collapsed = spaced.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(maxLength))
    }

    /// A name counts as user-assigned only when it is non-empty after
    /// sanitising and isn't a model name: the model ("Apple TV") or a
    /// generic hardware name such as "Apple TV 4K (4th generation)", which
    /// the simulator reports and which DD3 must not promise.
    public static func choose(system: String?, model: String) -> DeviceNameChoice {
        let name = sanitize(system ?? "")
        guard !name.isEmpty, !isModelName(name, model: model) else { return .fallback }
        return .assigned(name)
    }

    /// "Apple TV", "Apple TV 4K", "Apple TV HD", optionally followed by
    /// parenthesised details ("(4th generation)", "(at 1080p)").
    static func isModelName(_ name: String, model: String) -> Bool {
        if name.caseInsensitiveCompare(model) == .orderedSame { return true }
        let generic = #"^apple tv( 4k| hd)?( \([^)]*\))*$"#
        return name.lowercased().range(of: generic, options: .regularExpression) != nil
    }
}
