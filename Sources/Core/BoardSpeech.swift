import Foundation

/// What the board currently reads, in one sentence.
///
/// The canvas is hidden from VoiceOver on purpose: 810 flaps stepped through
/// one at a time is not a board, it is a filibuster. So the viewer owes it a
/// sentence instead, and this is that sentence.
///
/// It lives in Core because it is a property of the board's content and not
/// of the screen showing it — the Android port needs the same string — and
/// because it is the kind of thing that is only ever got right by being
/// tested, which a view modifier is not.
public enum BoardSpeech {

    /// A board with nothing on it still has to say something, or the viewer's
    /// one accessibility element reads as an unlabelled button.
    public static let blank = "Blank"

    /// A board of colour flaps and no letters — a flag, a block of red — has
    /// no text to read but is not blank either.
    public static let coloursOnly = "Coloured flaps, no text"

    /// The server's message when there is one, the flaps read back when there
    /// is not.
    ///
    /// The message wins because it is the text somebody typed, punctuation
    /// and capitals intact; reading the grid back can only approximate it,
    /// and the grid is what the message was rendered *into*.
    public static func spoken(message: String?, cells: [[BoardCell]]) -> String {
        if let message, let tidied = tidy(message) { return tidied }

        let lines = cells.compactMap { row in tidy(String(row.map(character(in:)))) }
        if !lines.isEmpty { return lines.joined(separator: ", ") }

        return hasColour(cells) ? coloursOnly : blank
    }

    private static func character(in cell: BoardCell) -> Character {
        switch cell {
        case .character(let character): return character
        // A colour flap and an unlit one both read as a gap between words.
        case .blank, .color: return " "
        }
    }

    private static func hasColour(_ cells: [[BoardCell]]) -> Bool {
        cells.contains { row in
            row.contains { cell in
                if case .color = cell { return true }
                return false
            }
        }
    }

    /// Folds every run of whitespace into one space, and returns nil when
    /// there are no words left.
    ///
    /// A split-flap board is mostly padding: a row centred by the server is
    /// twenty blanks around one word, and read literally that is a long
    /// silence followed by "HI".
    private static func tidy(_ text: String) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return nil }
        return words.joined(separator: " ")
    }
}
