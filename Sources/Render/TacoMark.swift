import CoreGraphics

/// FiestaBoard's taco, as resolution-independent geometry.
///
/// The mark used to ship as a 1024px PNG of shaded pseudo-pixel-art. Every
/// size tvOS asked for was an interpolation of it, so the icon arrived on a
/// 4K home screen soft-edged and obviously photographic — and the file alone
/// was a megabyte. The art is really a 30 × 26 grid of flat colours, so it is
/// stored as that grid and drawn as rectangles: exact at every size, a few
/// hundred bytes of source, and it compresses to almost nothing.
///
/// One definition serves the layered app icon, the static Top Shelf art and
/// the in-app Top Shelf posters, so the mark cannot drift between them.
/// Cells are authored with y increasing downward, the orientation SwiftUI,
/// UIKit and the asset generator all draw in.
public enum TacoMark {

    public static let columns = 30
    public static let rows = 26

    /// Width ÷ height of the mark.
    public static var aspect: CGFloat { CGFloat(columns) / CGFloat(rows) }

    // MARK: Palette

    public enum Ink {
        /// Brand amber — `Fiesta.Colors.brand`, FiestaUI `--primary`. The
        /// field the mark sits on; not used by the mark itself.
        public static let brand = srgb(0xf5a623)

        static func srgb(_ hex: UInt32) -> CGColor {
            CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                    green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255,
                    alpha: 1)
        }
    }

    /// Indexed by the letters in `art`. Order is paint order.
    private static let palette: [(key: Character, hex: UInt32)] = [
        ("f", 0x5b3d18),   // seasoned beef
        ("c", 0xc27719),   // tortilla, in shadow
        ("b", 0xe6a320),   // tortilla
        ("e", 0xeebb48),   // tortilla highlight
        ("g", 0x6eab23),   // lettuce
        ("h", 0xc1e16e),   // lime
        ("d", 0xac3117),   // tomato
        ("a", 0x130f31),   // outline
    ]

    // MARK: Output

    /// One flat colour and every cell that carries it, already merged into
    /// as few rectangles as the row runs allow.
    public struct Shape {
        public let path: CGPath
        public let fill: CGColor
    }

    /// The mark fitted inside `rect`, preserving `aspect` and centred.
    ///
    /// Paint the shapes in the order given. Whenever the cells are big
    /// enough, both the cell size and the origin are snapped to whole units
    /// so every edge lands on a pixel boundary: flat colour meeting flat
    /// colour with nothing blended in between, which is the whole point of
    /// drawing the mark rather than resampling it. Below that size the grid
    /// stays fractional and runs are outset by a hair so neighbouring cells
    /// overlap instead of leaving a seam.
    public static func shapes(in rect: CGRect) -> [Shape] {
        let available = min(rect.width / CGFloat(columns), rect.height / CGFloat(rows))
        guard available > 0 else { return [] }

        let snapped = available >= 4
        let cell = snapped ? available.rounded(.down) : available
        let bleed = snapped ? 0 : min(0.25, cell * 0.02)

        var originX = rect.midX - cell * CGFloat(columns) / 2
        var originY = rect.midY - cell * CGFloat(rows) / 2
        if snapped {
            originX.round()
            originY.round()
        }

        return palette.compactMap { key, hex in
            let path = CGMutablePath()
            var used = false
            for (row, line) in art.enumerated() {
                var column = 0
                let cells = Array(line)
                while column < cells.count {
                    guard cells[column] == key else { column += 1; continue }
                    let start = column
                    while column < cells.count, cells[column] == key { column += 1 }
                    path.addRect(CGRect(x: originX + CGFloat(start) * cell - bleed,
                                        y: originY + CGFloat(row) * cell - bleed,
                                        width: CGFloat(column - start) * cell + bleed * 2,
                                        height: cell + bleed * 2))
                    used = true
                }
            }
            return used ? Shape(path: path, fill: Ink.srgb(hex)) : nil
        }
    }

    // MARK: The mark

    /// 30 columns × 26 rows. `.` is transparent; every other character keys
    /// into `palette`. Quantised from the original artwork, one cell per
    /// block of the source grid.
    private static let art: [String] = [
        "...........aaaaaaaaaaa........",
        "..........affffaffaaaa........",
        "........aafeeeggdddggga.......",
        ".......aeecddgggfffffffaa.....",
        ".....aaegggedfgfeeeeeeeeca....",
        "....afcgcdcgggfcebbbbbbbbca...",
        "....acegedcgggfebbbbbbbbbea...",
        "...abbcddgggffebbbbbcbbbbbea..",
        "...aegggdggffebbbbbbcbbbbbea..",
        "...aegggggffebbbccbbbbbbbbba..",
        "..aefdddgfgebbbbbbbbbbbccbba..",
        "..aefdddgfcebbbbbbbbbbbccbba..",
        ".aagfddgfcbbbbbbbbbccbbbbbca..",
        "afbggffgfeebbbcbbbbbbbbbbcca..",
        "afbfffggfebbbbbbbbcbbbccccfaa.",
        "afbdffggfeebbbbbbbcbbbccccaaa.",
        "afbdffffebbcbbbbbbbbcccaaaggha",
        "afbfdddfebbbbbbbcccccaahhhghha",
        "afbdffdfebbbcccccfaaaahhhgggha",
        "afbfffffebbbcccfffafffhhhhggha",
        "afbfdfffebcccccaaaafgggghhggha",
        "afbcfffbccfaaaa..ahhhghggghhga",
        "aaabfffbaaaaa....agghghggghhga",
        "..abbbbcaa.......aafghhhhhgaa.",
        "...aaaaa..........aaffffffaa..",
        "....................aaaaaa....",
    ]
}
