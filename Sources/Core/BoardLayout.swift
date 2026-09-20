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

    /// Glyph size as a fraction of tile height, matching FiestaUI's board
    /// steps (28px tile → 16px text at the lg breakpoint).
    public static let fontSizeRatio = 0.40

    public var fontSize: Double { tileHeight * Self.fontSizeRatio }

    public static func make(rows: Int, cols: Int, cells: [[BoardCell]], tileHeight: Double) -> BoardLayout {
        guard rows > 0, cols > 0, tileHeight > 0 else {
            return BoardLayout(tiles: [], width: 0, height: 0, tileHeight: max(tileHeight, 0))
        }

        let h = tileHeight
        let tileWidth = h * BoardGeometry.tileWidthRatio
        let gutter = h * BoardGeometry.tileGutterRatio
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

    /// Lay the board out at whatever tile height makes it meet the screen
    /// the way `mode` asks for.
    public static func fitting(rows: Int, cols: Int, cells: [[BoardCell]],
                               in screen: CGSize, mode: BoardSizing,
                               diagonalInches: Double, calibration: Double,
                               colPitchIn: Double) throws -> BoardLayout {
        guard screen.width > 0, screen.height > 0 else {
            throw BoardGeometry.Error.nonPositive("screen \(screen.width)×\(screen.height)")
        }
        guard rows > 0, cols > 0 else {
            return BoardLayout(tiles: [], width: 0, height: 0, tileHeight: 0)
        }

        // Lay out once at a reference height, measure, then rescale. This is
        // the same two-pass shape the web viewer uses (render, measure the
        // grid, apply a transform) without needing a real measurement.
        let reference = 100.0
        let base = make(rows: rows, cols: cols, cells: cells, tileHeight: reference)

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

        return make(rows: rows, cols: cols, cells: cells, tileHeight: reference * scale)
    }
}
