import Foundation

/// Inputs to `BoardGeometry.autofitScale`.
public struct AutofitScaleInput: Sendable {
    public let screenWidthPx: Double
    public let screenHeightPx: Double
    public let diagonalInches: Double
    /// Grid columns — the physical width anchor.
    public let cols: Int
    /// Measured unscaled grid size, tiles only, no bezel.
    public let gridWidthPx: Double
    public let gridHeightPx: Double
    /// User fine-tune for screens that misreport resolution or overscan.
    public let calibration: Double
    public let colPitchIn: Double

    public init(screenWidthPx: Double, screenHeightPx: Double, diagonalInches: Double,
                cols: Int, gridWidthPx: Double, gridHeightPx: Double,
                calibration: Double = 1.0, colPitchIn: Double = BoardGeometry.colPitchIn) {
        self.screenWidthPx = screenWidthPx
        self.screenHeightPx = screenHeightPx
        self.diagonalInches = diagonalInches
        self.cols = cols
        self.gridWidthPx = gridWidthPx
        self.gridHeightPx = gridHeightPx
        self.calibration = calibration
        self.colPitchIn = colPitchIn
    }
}

/// Physical-scale math for a FiestaPanel.
///
/// The Swift twin of FiestaBoard's `src/panels/autofit.py` and
/// `web/src/lib/panel-scale.ts`. All three are pinned by the vectors in
/// `Spec/board-spec.json`, so drift fails a suite in every language.
///
/// Anchoring: a frameless Vestaboard Note is 24.5" wide for 15 columns, so
/// the column pitch is fixed. Row pitch follows the renderer's invariant
/// tile geometry (tile width 0.70·h, gutter 0.145·h on both axes → column
/// pitch 0.845·h, row pitch 1.145·h) rather than the Note unit's
/// bezel-heavy height — which is what lets one uniform scale keep both
/// axes physically true on screen.
public enum BoardGeometry {

    public enum Error: Swift.Error, Equatable {
        case nonPositive(String)
    }

    // Tile ratios (FiestaUI board-metrics TILE_RATIOS).
    public static let tileWidthRatio = 0.70
    public static let tileGutterRatio = 0.145
    public static let tileRadiusRatio = 0.075

    private static let colPitchRatio = tileWidthRatio + tileGutterRatio   // 0.845
    private static let rowPitchRatio = 1.0 + tileGutterRatio              // 1.145

    public static let noteUnitWidthIn = 24.5
    public static let noteCols = 15
    public static let noteRows = 3
    public static let maxNotesPerAxis = 8
    public static let maxFillStretch = 1.1

    public static let colPitchIn = noteUnitWidthIn / Double(noteCols)
    public static let rowPitchIn = colPitchIn * (rowPitchRatio / colPitchRatio)

    public static let blockWidthIn = Double(noteCols) * colPitchIn
    public static let blockHeightIn = Double(noteRows) * rowPitchIn

    /// Published Vestaboard unit widths, bezel included.
    public static let flagshipWidthIn = 41.2
    public static let flagshipCols = 22

    /// Physical column pitch for a device family.
    public static func colPitchIn(deviceType: String?) -> Double {
        deviceType == "flagship" ? flagshipWidthIn / Double(flagshipCols) : colPitchIn
    }

    /// (width, height) in inches of a screen with the given diagonal and aspect.
    public static func screenDimensionsIn(diagonal: Double,
                                          aspectW: Double = 16,
                                          aspectH: Double = 9) throws -> (width: Double, height: Double) {
        guard diagonal > 0 else { throw Error.nonPositive("diagonal \(diagonal)") }
        guard aspectW > 0, aspectH > 0 else { throw Error.nonPositive("aspect \(aspectW):\(aspectH)") }
        let hyp = hypot(aspectW, aspectH)
        return (diagonal * aspectW / hyp, diagonal * aspectH / hyp)
    }

    /// The largest true-scale grid of Note blocks that fits the screen.
    ///
    /// Always at least 1×1 — a screen smaller than one block gets a
    /// block-sized grid that the viewer shrinks to fit — and never more
    /// than `maxNotesPerAxis` per axis.
    public static func computeAutofitGrid(diagonal: Double,
                                          aspectW: Double = 16,
                                          aspectH: Double = 9) throws -> (notesWide: Int, notesTall: Int) {
        let (widthIn, heightIn) = try screenDimensionsIn(diagonal: diagonal, aspectW: aspectW, aspectH: aspectH)
        func clamp(_ blocks: Int) -> Int { max(1, min(maxNotesPerAxis, blocks)) }
        return (clamp(Int(floor(widthIn / blockWidthIn))),
                clamp(Int(floor(heightIn / blockHeightIn))))
    }

    /// Scale for a borderless auto-fit grid: flaps at true physical size,
    /// then gently stretched (≤ `maxFillStretch`) toward the nearest screen
    /// edge. Never shrinks below true size to fill — except when the grid
    /// overflows the screen at true size, where fitting beats a life-size
    /// crop of the top-left corner.
    public static func autofitScale(_ input: AutofitScaleInput) throws -> Double {
        guard input.gridWidthPx > 0, input.gridHeightPx > 0 else {
            throw Error.nonPositive("grid \(input.gridWidthPx)×\(input.gridHeightPx)")
        }
        guard input.cols > 0 else { throw Error.nonPositive("cols \(input.cols)") }
        guard input.screenWidthPx > 0, input.screenHeightPx > 0 else {
            throw Error.nonPositive("screen \(input.screenWidthPx)×\(input.screenHeightPx)")
        }
        guard input.diagonalInches > 0 else { throw Error.nonPositive("diagonal \(input.diagonalInches)") }

        let ppi = hypot(input.screenWidthPx, input.screenHeightPx) / input.diagonalInches
        let trueScale = (Double(input.cols) * input.colPitchIn * ppi) / input.gridWidthPx
        let fill = min(input.screenWidthPx / (input.gridWidthPx * trueScale),
                       input.screenHeightPx / (input.gridHeightPx * trueScale))
        let stretch = fill < 1 ? fill : min(maxFillStretch, fill)
        return trueScale * stretch * input.calibration
    }

    /// Scale that simply fits the grid to the screen — the app's default,
    /// used when the panel's grid was auto-fit for a different screen and
    /// physical accuracy would only buy black margins.
    public static func fitScale(gridWidthPx: Double, gridHeightPx: Double,
                                screenWidthPx: Double, screenHeightPx: Double) throws -> Double {
        guard gridWidthPx > 0, gridHeightPx > 0 else {
            throw Error.nonPositive("grid \(gridWidthPx)×\(gridHeightPx)")
        }
        guard screenWidthPx > 0, screenHeightPx > 0 else {
            throw Error.nonPositive("screen \(screenWidthPx)×\(screenHeightPx)")
        }
        return min(screenWidthPx / gridWidthPx, screenHeightPx / gridHeightPx)
    }
}
