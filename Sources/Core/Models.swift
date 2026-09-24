import Foundation

/// Night-time dimming window, evaluated against the TV's own clock.
public struct AutoDim: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let start: String   // "HH:MM", 24h
    public let end: String

    public init(enabled: Bool = false, start: String = "22:00", end: String = "07:00") {
        self.enabled = enabled
        self.start = start
        self.end = end
    }
}

/// A FiestaPanel: display configuration plus the geometry of its virtual board.
///
/// Field names follow the server's snake_case payload via CodingKeys rather
/// than a global key-decoding strategy, because `code62_glyph` does not
/// round-trip through automatic conversion.
public struct Panel: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let shortCode: Int
    public let name: String
    public let boardId: String
    public let screenDiagonalInches: Double
    public let screenAspectW: Double
    public let screenAspectH: Double
    public let calibrationScale: Double
    public let animationsEnabled: Bool
    public let backdrop: String
    public let autoDim: AutoDim
    public let deviceType: String?
    public let boardMissing: Bool
    public let rows: Int?
    public let cols: Int?
    public let boardColor: String?
    public let code62Glyph: Code62Glyph?

    enum CodingKeys: String, CodingKey {
        case id
        case shortCode = "short_code"
        case name
        case boardId = "board_id"
        case screenDiagonalInches = "screen_diagonal_inches"
        case screenAspectW = "screen_aspect_w"
        case screenAspectH = "screen_aspect_h"
        case calibrationScale = "calibration_scale"
        case animationsEnabled = "animations_enabled"
        case backdrop
        case autoDim = "auto_dim"
        case deviceType = "device_type"
        case boardMissing = "board_missing"
        case rows, cols
        case boardColor = "board_color"
        case code62Glyph = "code62_glyph"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        shortCode = try c.decodeIfPresent(Int.self, forKey: .shortCode) ?? 0
        name = try c.decode(String.self, forKey: .name)
        boardId = try c.decode(String.self, forKey: .boardId)
        screenDiagonalInches = try c.decodeIfPresent(Double.self, forKey: .screenDiagonalInches) ?? 55
        screenAspectW = try c.decodeIfPresent(Double.self, forKey: .screenAspectW) ?? 16
        screenAspectH = try c.decodeIfPresent(Double.self, forKey: .screenAspectH) ?? 9
        calibrationScale = try c.decodeIfPresent(Double.self, forKey: .calibrationScale) ?? 1
        animationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .animationsEnabled) ?? false
        backdrop = try c.decodeIfPresent(String.self, forKey: .backdrop) ?? "wall"
        autoDim = try c.decodeIfPresent(AutoDim.self, forKey: .autoDim) ?? AutoDim()
        deviceType = try c.decodeIfPresent(String.self, forKey: .deviceType)
        boardMissing = try c.decodeIfPresent(Bool.self, forKey: .boardMissing) ?? false
        rows = try c.decodeIfPresent(Int.self, forKey: .rows)
        cols = try c.decodeIfPresent(Int.self, forKey: .cols)
        boardColor = try c.decodeIfPresent(String.self, forKey: .boardColor)
        code62Glyph = try c.decodeIfPresent(Code62Glyph.self, forKey: .code62Glyph)
    }

    /// The glyph this panel's device actually prints for code 62.
    public var effectiveCode62: Code62Glyph {
        Code62Glyph.effective(deviceType: deviceType, configured: code62Glyph)
    }

    /// Board pigment behind the flaps. Anything unrecognised is black.
    public var backgroundColor: BoardColor {
        boardColor.flatMap { BoardColor(rawValue: $0) } ?? .black
    }
}

/// The virtual board's current content.
public struct PanelFrame: Decodable, Equatable, Sendable {
    public let characters: [[Int]]?
    public let message: String?
    public let rows: Int
    public let cols: Int
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case characters, message, rows, cols
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        characters = try c.decodeIfPresent([[Int]].self, forKey: .characters)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 0
        cols = try c.decodeIfPresent(Int.self, forKey: .cols) ?? 0
        if let raw = try c.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = ISO8601DateFormatter.fiestaDate(from: raw)
        } else {
            updatedAt = nil
        }
    }

    public init(characters: [[Int]]?, message: String?, rows: Int, cols: Int, updatedAt: Date?) {
        self.characters = characters
        self.message = message
        self.rows = rows
        self.cols = cols
        self.updatedAt = updatedAt
    }
}

extension ISO8601DateFormatter {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// The server emits fractional seconds on some paths and not others.
    static func fiestaDate(from string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }
}

public struct AuthStatus: Decodable, Equatable, Sendable {
    public let enabled: Bool
    public let setupRequired: Bool
    public let authenticated: Bool
    public let username: String?
    public let mode: String
    public let firstRun: Bool

    enum CodingKeys: String, CodingKey {
        case enabled, authenticated, username, mode
        case setupRequired = "setup_required"
        case firstRun = "first_run"
    }
}

/// A page or schedule that no longer fits a reshaped grid.
public struct IncompatibleReference: Decodable, Equatable, Sendable {
    public let type: String?
    public let id: String?
    public let name: String?
}

public struct PanelUpdateResult: Sendable {
    public let panel: Panel
    public let incompatibleReferences: [IncompatibleReference]
}

public enum FiestaError: Error, Equatable {
    case unauthorized
    case setupRequired
    case notFound(String)
    case http(Int)
    case transport(String)
    case decoding(String)

    /// What to put on a TV screen for this failure.
    ///
    /// Every case here used to surface as "Couldn't reach your FiestaBoard.
    /// Check it's still on" — including a board that answered in
    /// milliseconds with 429, with 500, or with a payload this app could not
    /// parse. Blaming the network for those sends people to check cables
    /// and power while the board sits there replying, which is the worst
    /// possible thing to tell someone standing in front of a working board.
    ///
    /// Only `.transport` is actually an unreachable board.
    public var userMessage: String {
        switch self {
        case .transport:
            return "Couldn't reach your FiestaBoard. Check it's still on and on this network."
        case .unauthorized:
            return "Your saved sign-in was refused. Sign in again."
        case .setupRequired:
            return "This FiestaBoard has no account yet. Finish setup in the FiestaBoard app."
        case .notFound(let detail):
            return detail
        case .http(429):
            return "Your FiestaBoard is refusing sign-ins after too many failed attempts. "
                 + "Wait a minute, then sign in again."
        case .http(let status) where (500..<600).contains(status):
            return "Your FiestaBoard answered with an error (HTTP \(status)). Check its logs."
        case .http(let status):
            return "Your FiestaBoard refused the request (HTTP \(status))."
        case .decoding:
            return "Your FiestaBoard replied in a format this app doesn't understand. "
                 + "It may be running a newer version than this app supports."
        }
    }
}

extension Panel {
    /// "30 × 12", or a plain statement when the virtual board is gone.
    public var gridDescription: String {
        guard !boardMissing, let rows, let cols else { return "No board" }
        return "\(cols) × \(rows)"
    }

    /// The screen this panel's grid was auto-fit for — which is not
    /// necessarily the screen it is about to be shown on.
    public var screenDescription: String {
        let inches = screenDiagonalInches
        let rounded = inches.rounded()
        let text = abs(inches - rounded) < 0.05 ? String(Int(rounded)) : String(format: "%.1f", inches)
        return "Built for a \(text)\" screen"
    }
}
