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
    private let rawRenderStyle: String?
    public let deviceModelSpec: MatrixDisplay?
    private let rawMatrixSizing: String?
    public let matrixPitchMillimeters: Double?
    public let supportsMatrixSettings: Bool
    public var matrixSizing: MatrixSizing? { MatrixSizing(serverValue: rawMatrixSizing) }
    public var matrixPresentation: MatrixPresentation? {
        guard renderStyle == .ledMatrix, let mode = MatrixSizing(serverValue: rawMatrixSizing) else { return nil }
        return .init(sizing: mode, diagonalInches: screenDiagonalInches, pitchMillimeters: matrixPitchMillimeters ?? 6, calibrationScale: calibrationScale)
    }
    /// Shared calibration also applies when sizing follows this TV's preference.
    public func effectiveMatrixPresentation(fallback: MatrixPresentation) -> MatrixPresentation {
        matrixPresentation ?? MatrixPresentation(sizing: fallback.sizing, diagonalInches: fallback.diagonalInches,
                                                  pitchMillimeters: fallback.pitchMillimeters, calibrationScale: calibrationScale)
    }

    public var renderStyle: PanelRenderStyle { rawRenderStyle.flatMap(PanelRenderStyle.init(rawValue:)) ?? .splitFlap }
    public var supportsRenderStyle: Bool { rawRenderStyle != nil }
    public var matrixDisplay: MatrixDisplay {
        (deviceModelSpec ?? .standard).containingCellGrid(rows: rows, columns: cols)
    }

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
        case rawRenderStyle = "render_style"
        case deviceModelSpec = "device_model_spec"
        case rawMatrixSizing = "matrix_sizing"
        case matrixPitchMillimeters = "matrix_pitch_mm"
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
        // Decoded as a raw String and mapped, the way `boardColor` above is.
        // `decodeIfPresent` on a RawRepresentable returns nil only for an
        // absent or null key: an unrecognised *value* throws and takes the
        // whole Panel with it. The viewer re-reads this config every ten
        // seconds, so the day the server learns a new glyph, every shipped
        // TV would stop polling over a field it can already default.
        let rawCode62 = try c.decodeIfPresent(String.self, forKey: .code62Glyph)
        code62Glyph = rawCode62.flatMap(Code62Glyph.init(rawValue:))
        rawRenderStyle = try c.decodeIfPresent(String.self, forKey: .rawRenderStyle)
        deviceModelSpec = try c.decodeIfPresent(MatrixDisplay.self, forKey: .deviceModelSpec)
        supportsMatrixSettings = c.contains(.rawMatrixSizing) && c.contains(.matrixPitchMillimeters)
        rawMatrixSizing = try c.decodeIfPresent(String.self, forKey: .rawMatrixSizing)
        matrixPitchMillimeters = try c.decodeIfPresent(Double.self, forKey: .matrixPitchMillimeters)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(shortCode, forKey: .shortCode)
        try c.encode(name, forKey: .name)
        try c.encode(boardId, forKey: .boardId)
        try c.encode(screenDiagonalInches, forKey: .screenDiagonalInches)
        try c.encode(screenAspectW, forKey: .screenAspectW)
        try c.encode(screenAspectH, forKey: .screenAspectH)
        try c.encode(calibrationScale, forKey: .calibrationScale)
        try c.encode(animationsEnabled, forKey: .animationsEnabled)
        try c.encode(backdrop, forKey: .backdrop)
        try c.encode(autoDim, forKey: .autoDim)
        try c.encode(boardMissing, forKey: .boardMissing)
        try c.encodeIfPresent(deviceType, forKey: .deviceType)
        try c.encodeIfPresent(rows, forKey: .rows)
        try c.encodeIfPresent(cols, forKey: .cols)
        try c.encodeIfPresent(boardColor, forKey: .boardColor)
        try c.encodeIfPresent(code62Glyph, forKey: .code62Glyph)
        try c.encodeIfPresent(rawRenderStyle, forKey: .rawRenderStyle)
        try c.encodeIfPresent(deviceModelSpec, forKey: .deviceModelSpec)
        try c.encodeIfPresent(matrixPitchMillimeters, forKey: .matrixPitchMillimeters)
        if supportsMatrixSettings {
            try c.encode(rawMatrixSizing, forKey: .rawMatrixSizing)
        } else {
            try c.encodeIfPresent(rawMatrixSizing, forKey: .rawMatrixSizing)
        }
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
    /// The largest grid this app will believe from the wire.
    ///
    /// The biggest real board is 45x18. Unbounded, `rows * cols` reached
    /// `BoardLayout.make`'s `reserveCapacity` as an unchecked Int multiply,
    /// so `{"rows":4000000000,"cols":4000000000}` trapped and 100000 squared
    /// was a ten-billion-element append loop — and a configured TV relaunches
    /// straight into the viewer, so either one made the app unlaunchable with
    /// no way back out from the remote. Clamping in this initialiser rather
    /// than in a consumer is deliberate: it is the one point every consumer
    /// passes through, including the panel list, which builds its preview
    /// straight off the decoded frame.
    public static let maxDimension = 256

    public let characters: [[Int]]?
    public let richCells: [[MatrixCell]]?
    public let message: String?
    public let rows: Int
    public let cols: Int
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case characters, message, rows, cols
        case richCells = "cells"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        let rawRows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 0
        let rawCols = try c.decodeIfPresent(Int.self, forKey: .cols) ?? 0
        rows = min(max(rawRows, 0), Self.maxDimension)
        cols = min(max(rawCols, 0), Self.maxDimension)
        let rowLimit = rows
        let colLimit = cols
        characters = try c.decodeIfPresent([[Int]].self, forKey: .characters).map {
            $0.prefix(rowLimit).map { Array($0.prefix(colLimit)) }
        }
        richCells = try c.decodeIfPresent([[MatrixCell]].self, forKey: .richCells).map {
            $0.prefix(rowLimit).map { Array($0.prefix(colLimit)) }
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = ISO8601DateFormatter.fiestaDate(from: raw)
        } else {
            updatedAt = nil
        }
    }

    public init(characters: [[Int]]?, message: String?, rows: Int, cols: Int, updatedAt: Date?, richCells: [[MatrixCell]]? = nil) {
        self.characters = characters
        self.message = message
        self.rows = min(max(rows, 0), Self.maxDimension)
        self.cols = min(max(cols, 0), Self.maxDimension)
        self.updatedAt = updatedAt
        self.richCells = richCells
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

    private enum CodingKeys: String, CodingKey {
        case type, id, name, surface
        case pageID = "page_id"
        case pageName = "page_name"
    }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        type = try fields.decodeIfPresent(String.self, forKey: .surface)
            ?? fields.decodeIfPresent(String.self, forKey: .type)
        id = try fields.decodeIfPresent(String.self, forKey: .pageID)
            ?? fields.decodeIfPresent(String.self, forKey: .id)
        name = try fields.decodeIfPresent(String.self, forKey: .pageName)
            ?? fields.decodeIfPresent(String.self, forKey: .name)
    }
}

public struct PanelUpdateResult: Sendable {
    public let panel: Panel
    public let incompatibleReferences: [IncompatibleReference]
}

public enum FiestaError: Error, Equatable {
    case unauthorized
    case setupRequired
    case notFound(String)
    /// The board answered, but is not serving yet.
    ///
    /// Deliberately carries no detail. The only 503 this app can receive is
    /// the fixed `{"detail":"Service is starting up, please try again
    /// shortly"}` nginx returns from its own `@api_starting` location while
    /// FastAPI is still coming up: none of the endpoints this app calls
    /// (`/auth/*`, `/panels`, `/panel/*`) declares an application 503, and
    /// nginx keeps `proxy_intercept_errors off` so the ones that do elsewhere
    /// never reach here. A fixed internal string is worse on a TV than the
    /// app's own copy below, and a payload nothing reads only invites one.
    case unavailable
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
            // "Finish setup in the FiestaBoard app" was circular: this *is*
            // the FiestaBoard app as far as the person reading it is
            // concerned. Account creation only exists on the board's own
            // web page. This is the only copy of it: `AppModel` reads it from
            // here, because two spellings of the first sentence a brand-new
            // board's owner ever reads will drift the first time one is edited.
            return "This FiestaBoard has no account yet. Open your board's web page in a browser "
                 + "on a phone or computer, create your account there, then choose the board "
                 + "again here."
        case .notFound(let detail):
            return detail
        case .unavailable:
            // nginx answers 503 "Service is starting up" for the 30-60s
            // after a power cut, before FastAPI is listening. That is the
            // most common failure anyone actually sees, and the 5xx line
            // below sent them to read the logs of a machine that is merely
            // booting.
            return "Your FiestaBoard is still starting up. This usually takes under a minute."
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
        // `board_missing` is the server saying the board row was deleted,
        // not that one is waiting to be attached.
        guard !boardMissing, let rows, let cols else { return "Board removed" }
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
