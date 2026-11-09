import CoreGraphics
import Foundation

/// How the board is sized against the screen.
public enum BoardSizing: String, Codable, CaseIterable, Sendable {
    /// Fill the screen, preserving aspect. The default: a panel's grid was
    /// auto-fit for whatever TV its owner typed in, which is rarely this one.
    case fit
    /// Flaps at real Vestaboard size, accepting margins.
    case trueScale
}

/// One flap, positioned.
public struct TileRect: Equatable, Sendable {
    public let row: Int
    public let col: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let radius: Double
    public let cell: BoardCell
}

/// A board reduced to rectangles.
///
/// Pure geometry with no drawing: the renderer paints this, the tests do
/// arithmetic on it, and the future Compose implementation reuses the shape
/// of it verbatim.
public struct BoardLayout: Sendable {

    public let tiles: [TileRect]
    public let width: Double
    public let height: Double
    public let tileHeight: Double
    /// A10: one bezel per Note for a note array, row by row; empty for a
    /// merged grid.
    public let notes: [NoteBezel]
    public let bezelBorder: Double
    public let bezelRadius: Double

    public init(tiles: [TileRect], width: Double, height: Double, tileHeight: Double,
                notes: [NoteBezel] = [], bezelBorder: Double = 0, bezelRadius: Double = 0) {
        self.tiles = tiles
        self.width = width
        self.height = height
        self.tileHeight = tileHeight
        self.notes = notes
        self.bezelBorder = bezelBorder
        self.bezelRadius = bezelRadius
    }

    /// Glyph size as a fraction of tile height, matching FiestaUI's board
    /// steps (28px tile → 16px text at the lg breakpoint).
    public static let fontSizeRatio = 0.40

    public var fontSize: Double { tileHeight * Self.fontSizeRatio }

    /// The size `make` would produce, without building its tiles.
    ///
    /// Laying a board out is a two-pass job and only the second pass needs
    /// the tiles; so is asking whether a grid suits a screen. An 85" panel
    /// is 810 tiles, so measuring through `make` allocated a whole board to
    /// read two numbers off it.
    public static func size(rows: Int, cols: Int, tileHeight: Double,
                            noteArray: Bool = false) -> (width: Double, height: Double) {
        guard rows > 0, cols > 0, tileHeight > 0 else { return (0, 0) }
        if noteArray {
            return (NoteArray.extent(count: cols, per: NoteArray.cols, tile: BoardGeometry.tileWidthRatio) * tileHeight,
                    NoteArray.extent(count: rows, per: NoteArray.rows, tile: 1) * tileHeight)
        }
        let (tileWidth, gutter) = metrics(tileHeight: tileHeight)
        let colPitch = tileWidth + gutter
        let rowPitch = tileHeight + gutter
        // Borderless: the trailing gutter is not part of the board.
        return (Double(cols) * colPitch - gutter, Double(rows) * rowPitch - gutter)
    }

    /// A tile's width and the gutter, from its height, as FiestaUI
    /// `board-metrics.ts` derives them: each rounded to a whole point
    /// (`width = round(h × 0.70)`, `gutter = round(h × 0.145)`), so the
    /// web, Figma and the TV agree at integer pixels. At 07b's 46 pt tile
    /// that is 32 / 7, and a 29 × 12 board of 1124 × 629 (`149:182628`);
    /// unrounded, it drifted 3.4 pt over 29 columns. The radius is
    /// paint-only and stays exact, as in FiestaUI. (Note arrays, A10, keep
    /// their own seam geometry.)
    public static func metrics(tileHeight h: Double) -> (width: Double, gutter: Double) {
        ((h * BoardGeometry.tileWidthRatio).rounded(), (h * BoardGeometry.tileGutterRatio).rounded())
    }

    public static func make(rows: Int, cols: Int, cells: [[BoardCell]], tileHeight: Double,
                            noteArray: Bool = false) -> BoardLayout {
        // The dimension ceiling is a second belt behind `PanelFrame`'s decode
        // clamp: `rows * cols` below is an unchecked Int multiply feeding
        // `reserveCapacity`, and a grid assembled in code rather than decoded
        // would otherwise still reach it. An empty layout is what every
        // caller already handles for a grid it cannot draw.
        guard rows > 0, cols > 0, tileHeight > 0,
              rows <= PanelFrame.maxDimension, cols <= PanelFrame.maxDimension else {
            return BoardLayout(tiles: [], width: 0, height: 0, tileHeight: max(tileHeight, 0))
        }

        if noteArray { return makeNotes(rows: rows, cols: cols, cells: cells, tileHeight: tileHeight) }

        let h = tileHeight
        let (tileWidth, gutter) = metrics(tileHeight: h)
        let radius = h * BoardGeometry.tileRadiusRatio
        let colPitch = tileWidth + gutter
        let rowPitch = h + gutter

        var tiles: [TileRect] = []
        tiles.reserveCapacity(rows * cols)
        for row in 0..<rows {
            for col in 0..<cols {
                // Short or ragged frames pad with blanks: a reshape in flight
                // is a normal transient state, not a crash.
                let cell: BoardCell = (row < cells.count && col < cells[row].count)
                    ? cells[row][col] : .blank
                tiles.append(TileRect(row: row, col: col,
                                      x: Double(col) * colPitch,
                                      y: Double(row) * rowPitch,
                                      width: tileWidth, height: h, radius: radius,
                                      cell: cell))
            }
        }

        // Borderless: the trailing gutter is not part of the board.
        return BoardLayout(tiles: tiles,
                           width: Double(cols) * colPitch - gutter,
                           height: Double(rows) * rowPitch - gutter,
                           tileHeight: h)
    }

    /// A10 (DD5): a note array as separate Notes. Every cell is drawn; seams
    /// fall every 15 columns and 3 rows; each Note gets its own bezel, and
    /// a trailing partial Note's is cut open on its free side.
    private static func makeNotes(rows: Int, cols: Int, cells: [[BoardCell]], tileHeight h: Double) -> BoardLayout {
        let tileWidth = h * BoardGeometry.tileWidthRatio
        let radius = h * BoardGeometry.tileRadiusRatio
        let xs = (0..<cols).map { NoteArray.offset($0, per: NoteArray.cols, tile: BoardGeometry.tileWidthRatio) * h }
        let ys = (0..<rows).map { NoteArray.offset($0, per: NoteArray.rows, tile: 1) * h }

        var tiles: [TileRect] = []
        tiles.reserveCapacity(rows * cols)
        for row in 0..<rows {
            for col in 0..<cols {
                let cell: BoardCell = (row < cells.count && col < cells[row].count)
                    ? cells[row][col] : .blank
                tiles.append(TileRect(row: row, col: col, x: xs[col], y: ys[row],
                                      width: tileWidth, height: h, radius: radius, cell: cell))
            }
        }

        let across = NoteArray.edges(count: cols, per: NoteArray.cols, tile: BoardGeometry.tileWidthRatio)
        let down = NoteArray.edges(count: rows, per: NoteArray.rows, tile: 1)
        let notes = down.flatMap { y in
            across.map { x in
                NoteBezel(rect: CGRect(x: x.start * h, y: y.start * h,
                                       width: (x.end - x.start) * h, height: (y.end - y.start) * h),
                          openRight: x.open, openBottom: y.open)
            }
        }
        return BoardLayout(tiles: tiles,
                           width: (across.last?.end ?? 0) * h,
                           height: (down.last?.end ?? 0) * h,
                           tileHeight: h, notes: notes,
                           bezelBorder: NoteArray.borderRatio * h,
                           bezelRadius: NoteArray.radiusRatio * h)
    }

    /// Lay the board out at whatever tile height makes it meet the screen
    /// the way `mode` asks for.
    public static func fitting(rows: Int, cols: Int, cells: [[BoardCell]],
                               in screen: CGSize, mode: BoardSizing,
                               diagonalInches: Double, calibration: Double,
                               colPitchIn: Double, noteArray: Bool = false) throws -> BoardLayout {
        guard screen.width > 0, screen.height > 0 else {
            throw BoardGeometry.Error.nonPositive("screen \(screen.width)×\(screen.height)")
        }
        guard rows > 0, cols > 0 else {
            return BoardLayout(tiles: [], width: 0, height: 0, tileHeight: 0)
        }

        // Measure once at a reference height, then rescale. This is the
        // same two-pass shape the web viewer uses (render, measure the grid,
        // apply a transform) without needing a real measurement.
        let reference = 100.0
        let base = size(rows: rows, cols: cols, tileHeight: reference, noteArray: noteArray)

        let scale: Double
        switch mode {
        case .fit:
            scale = try BoardGeometry.fitScale(gridWidthPx: base.width, gridHeightPx: base.height,
                                               screenWidthPx: Double(screen.width),
                                               screenHeightPx: Double(screen.height))
        case .trueScale:
            scale = try BoardGeometry.autofitScale(
                AutofitScaleInput(screenWidthPx: Double(screen.width),
                                  screenHeightPx: Double(screen.height),
                                  diagonalInches: diagonalInches,
                                  cols: cols,
                                  gridWidthPx: base.width, gridHeightPx: base.height,
                                  calibration: calibration, colPitchIn: colPitchIn))
        }

        // Whole-point widths and gutters can round a fitted board a few
        // points past the screen. Step the tile height down until it fits.
        // True scale keeps its physical size: calibration may overflow.
        var tileHeight = reference * scale
        while mode == .fit, tileHeight > 0.1 {
            let fitted = size(rows: rows, cols: cols, tileHeight: tileHeight, noteArray: noteArray)
            if fitted.width <= Double(screen.width) + 1e-9, fitted.height <= Double(screen.height) + 1e-9 { break }
            tileHeight -= 0.05
        }
        return make(rows: rows, cols: cols, cells: cells, tileHeight: tileHeight, noteArray: noteArray)
    }
}
