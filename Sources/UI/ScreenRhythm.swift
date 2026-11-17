import CoreGraphics

/// 07b's vertical rhythm on the A1–A3 screens (Connect, device sign-in,
/// Panels): the heading block, eyebrow at y 110, ends at **y 268** (the
/// subtitle's bottom: `166:147312`, `166:147407`, `166:147718`), and the
/// content hangs from there. With SF in place of 07b's Inter the heading
/// itself ends near y 251, so the block keeps 07b's height and the content
/// lands where the frames put it.
enum ScreenRhythm {
    static let headingBottom: CGFloat = 268
    /// The heading block's height inside the 80/60 title-safe area.
    static var headingHeight: CGFloat { headingBottom - PlatformTV.safeTopBottom }
    /// Where the content below the heading starts: one gutter down.
    static var contentTop: CGFloat { headingBottom + Fiesta.Metrics.gutter }
}
