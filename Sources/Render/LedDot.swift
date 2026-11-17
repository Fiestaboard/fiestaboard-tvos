import SwiftUI

/// The shape of one LED (DESIGN-DELTAS DD24), shared by every painter that
/// draws dots: `MatrixCanvas` (viewer, cards, Top Shelf, transition
/// snapshots), its tiled surround, and `MatrixMarqueeLayers`.
///
/// It is FiestaUI `LedMatrixDisplay`'s `traceDot`: a dot of 6 device pixels
/// or more is a square with corners rounded to 0.15 of the dot; a smaller dot
/// stays square (rounding a few pixels only blurs them); "round" is an oval.
/// Every other `pixelShape`, the hub's "square" default included, is the
/// rounded square.
enum LedDot {
    static let cornerRatio: CGFloat = 0.15
    /// FiestaUI's `size >= 6`, in device pixels.
    static let minimumRoundedPixels: CGFloat = 6

    static func isRound(_ display: MatrixDisplay) -> Bool {
        display.appearance?.pixelShape == "round"
    }

    /// The corner radius of a `dot` (in points) drawn at `scale` device
    /// pixels per point, in points.
    static func cornerRadius(dot: CGFloat, scale: CGFloat) -> CGFloat {
        dot * max(1, scale) >= minimumRoundedPixels ? dot * cornerRatio : 0
    }

    /// One dot, or a glow around it: `grow` points outward, with corners
    /// concentric to the dot's.
    static func path(_ rect: CGRect, round: Bool, corner: CGFloat, grow: CGFloat = 0) -> Path {
        let rect = rect.insetBy(dx: -grow, dy: -grow)
        if round { return Path(ellipseIn: rect) }
        // Circular arcs, like canvas `roundRect`; SwiftUI defaults to `.continuous`.
        return corner > 0 ? Path(roundedRect: rect, cornerRadius: corner + grow, style: .circular) : Path(rect)
    }
}
