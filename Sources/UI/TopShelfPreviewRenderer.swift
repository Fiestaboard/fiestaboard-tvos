import SwiftUI

/// The carousel hero: a static picture of the latest fetched frame, using
/// the same rendering as the panel grid. Home reads only these local
/// images, never the server.
///
/// A7 (07b A9 `166:207117`, hero `…;184:181334`): the carousel image is the
/// full screen, 1920×1080 pt (HIG), supplied at @1x and @2x. The system
/// draws the text column (contextTitle, title, Play / More Info at x 80–744)
/// and its scrims over the leading edge, so the board sits right of it in
/// 07b's slot `…;184:183320`, on the viewer's true black.
@MainActor
enum TopShelfPreviewRenderer {
    static let size = CGSize(width: 1920, height: 1080)
    /// 07b `I166:207117;149:182603;184:183320`: the board, aspect-fit.
    static let boardSlot = CGRect(x: 700, y: 11, width: 1180, height: 678)

    /// One hero at both scales.
    struct Hero {
        let oneX: CGImage
        let twoX: CGImage
    }

    static func hero(panel: Panel, preview: PanelPreview) -> Hero? {
        guard preview.rows > 0, preview.cols > 0 else { return unavailableHero }
        BoardFont.registerIfNeeded()
        return hero(PanelPreviewBoard(panel: panel, preview: preview))
    }

    /// A failed frame must never look like an invented board message.
    static let unavailableHero: Hero? = hero(
        VStack(spacing: 30) {
            Image(systemName: "rectangle.slash").font(.system(size: 100))
            Text("Preview unavailable").font(.system(size: 64, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.7)))

    private static func hero(_ board: some View) -> Hero? {
        guard let oneX = render(board, scale: 1), let twoX = render(board, scale: 2) else { return nil }
        return Hero(oneX: oneX, twoX: twoX)
    }

    private static func render(_ board: some View, scale: CGFloat) -> CGImage? {
        #if DEBUG
        let began = CACurrentMediaTime()
        defer { PanelNavigationProbe.shared.event("topshelf.render", began: began) }
        #endif
        let canvas = ZStack(alignment: .topLeading) {
            Color.black
            board
                .frame(width: boardSlot.width, height: boardSlot.height)
                .offset(x: boardSlot.minX, y: boardSlot.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .environment(\.displayScale, scale)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }
}
