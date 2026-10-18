import SwiftUI

/// A static picture of the latest fetched frame, using the same rendering
/// as the panel grid. Home reads only this local image, never the server.
@MainActor
enum TopShelfPreviewRenderer {
    static let size = CGSize(width: 1920, height: 1080)

    static func image(panel: Panel, preview: PanelPreview) -> Data? {
        guard preview.rows > 0, preview.cols > 0 else { return unavailable }
        BoardFont.registerIfNeeded()
        return render(PanelPreviewBoard(panel: panel, preview: preview))
    }

    /// A failed frame must never look like an invented board message.
    static let unavailable: Data? = render(
        VStack(spacing: 30) {
            Image(systemName: "rectangle.slash").font(.system(size: 100))
            Text("Preview unavailable").font(.system(size: 64, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.7)))

    private static func render(_ content: some View) -> Data? {
        let canvas = content
        .frame(width: size.width, height: size.height)
        .background(.black)
        .environment(\.colorScheme, .dark)
        .environment(\.displayScale, 1)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage?.pngData()
    }
}
