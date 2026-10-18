import SwiftUI

/// A static picture of the latest fetched frame, using the same rendering
/// as the panel grid. Home reads only this local image, never the server.
@MainActor
enum TopShelfPreviewRenderer {
    static let size = CGSize(width: 1920, height: 1080)

    static func image(panel: Panel, preview: PanelPreview) -> CGImage? {
        guard preview.rows > 0, preview.cols > 0 else { return unavailable }
        BoardFont.registerIfNeeded()
        return render(PanelPreviewBoard(panel: panel, preview: preview).padding(64))
    }

    /// A failed frame must never look like an invented board message.
    static let unavailable: CGImage? = render(
        VStack(spacing: 30) {
            Image(systemName: "rectangle.slash").font(.system(size: 100))
            Text("Preview unavailable").font(.system(size: 64, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.7)))

    private static func render(_ content: some View) -> CGImage? {
        #if DEBUG
        let began = CACurrentMediaTime()
        defer { PanelNavigationProbe.shared.event("topshelf.render", began: began) }
        #endif
        let canvas = content
        .frame(width: size.width, height: size.height)
        .background(Fiesta.Colors.surface)
        .environment(\.colorScheme, .dark)
        .environment(\.displayScale, 1)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.cgImage
    }
}
