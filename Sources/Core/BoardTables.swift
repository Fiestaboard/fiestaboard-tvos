import Foundation

/// One cell of a board frame.
public enum BoardCell: Equatable, Sendable {
    case blank
    case character(Character)
    case color(BoardColor)
}

/// The eight board pigments. Hex values are FiestaUI's `BOARD_COLORS`.
public enum BoardColor: String, CaseIterable, Sendable {
    case red, orange, yellow, green, blue, violet, white, black

    public var hex: String {
        switch self {
        case .red:    return "#eb4034"
        case .orange: return "#f5a623"
        case .yellow: return "#f8e71c"
        case .green:  return "#7ed321"
        case .blue:   return "#4a90d9"
        case .violet: return "#9b59b6"
        case .white:  return "#ffffff"
        // Board black is #1a1a1a, never pure black: a real flap reflects light.
        case .black:  return "#1a1a1a"
        }
    }

    /// Character codes 63-71. 70 and 71 are both black (71 is "filled").
    public init?(code: Int) {
        switch code {
        case 63: self = .red
        case 64: self = .orange
        case 65: self = .yellow
        case 66: self = .green
        case 67: self = .blue
        case 68: self = .violet
        case 69: self = .white
        case 70, 71: self = .black
        default: return nil
        }
    }
}

/// Which glyph character code 62 shows. Note-family devices print a heart
/// where a Flagship prints a degree sign.
public enum Code62Glyph: String, Codable, Sendable {
    case degree, heart

    public var character: Character {
        self == .heart ? "♥" : "°"
    }

    /// Mirrors FiestaUI's `effectiveCode62Glyph`: note devices are always
    /// hearts regardless of configuration; everything else honours the
    /// configured value and defaults to degree.
    public static func effective(deviceType: String?, configured: Code62Glyph?) -> Code62Glyph {
        if deviceType == "note" || deviceType == "note_array" { return .heart }
        return configured ?? .degree
    }
}

/// Character-code lookup for board frames.
///
/// Codes 0-71, per https://docs.vestaboard.com/docs/characterCodes. Codes
/// 43, 45, 51, 57, 58 and 61 are not defined in the official table and
/// render blank. Code 62 is device-dependent (see `Code62Glyph`).
public enum BoardTables {

    /// Printable glyphs for codes 0-61. Index 62 is handled separately
    /// because it depends on the device; 63-71 are colors.
    private static let glyphs: [Character?] = {
        var table: [Character?] = [nil]                                  // 0: blank
        table += "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { Optional($0) }       // 1-26
        table += "1234567890".map { Optional($0) }                       // 27-36
        // 37-61, with nil at the officially undefined codes.
        let tail: [Character?] = [
            "!", "@", "#", "$", "(", ")", nil, "-", nil, "+", "&", "=",
            ";", ":", nil, "'", "\"", "%", ",", ".", nil, nil, "/", "?", nil,
        ]
        table += tail
        return table
    }()

    private static let codeByGlyph: [Character: Int] = {
        var codes: [Character: Int] = [:]
        for (code, glyph) in glyphs.enumerated() {
            if let glyph { codes[glyph] = code }
        }
        codes["°"] = 62
        codes["♥"] = 62
        return codes
    }()

    /// Canonical drum position for a painted cell. Both black codes paint the
    /// same face, so the return path uses code 70.
    public static func code(for cell: BoardCell) -> Int {
        switch cell {
        case .blank: return 0
        case .character(let glyph): return codeByGlyph[glyph] ?? 0
        case .color(let color):
            switch color {
            case .red: return 63
            case .orange: return 64
            case .yellow: return 65
            case .green: return 66
            case .blue: return 67
            case .violet: return 68
            case .white: return 69
            case .black: return 70
            }
        }
    }

    public static func cell(forCode code: Int, code62: Code62Glyph) -> BoardCell {
        if code == 62 { return .character(code62.character) }
        if let color = BoardColor(code: code) { return .color(color) }
        guard code >= 0, code < glyphs.count, let glyph = glyphs[code] else { return .blank }
        return .character(glyph)
    }

    /// Convenience for a whole frame.
    public static func cells(from characters: [[Int]], code62: Code62Glyph) -> [[BoardCell]] {
        characters.map { row in row.map { cell(forCode: $0, code62: code62) } }
    }
}
