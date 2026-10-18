import SwiftUI

/// The browser moves a picture of each board during focus and scrolling.
/// The original renderer remains the source of truth for its appearance.
struct PanelPreviewThumbnail: View {
    let panel: Panel
    let preview: PanelPreview
    let cache: PanelPreviewImageCache

    @Environment(\.self) private var environment
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        #if DEBUG
        if PanelNavigationProbe.blankPreviews {
            Color.black.accessibilityHidden(true)
        } else {
            thumbnail
        }
        #else
        thumbnail
        #endif
    }

    private var thumbnail: some View {
        GeometryReader { proxy in
            let request = PanelPreviewImageCache.Request(
                panel: panel, preview: preview, size: proxy.size,
                scale: displayScale, colorScheme: colorScheme,
                reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased)
            if proxy.size.width > 1, proxy.size.height > 1,
               let image = cache.image(for: request, render: { Self.render(request, environment: environment) }) {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                PanelPreviewBoard(panel: panel, preview: preview)
            }
        }
        .accessibilityHidden(true)
    }

    @MainActor
    static func render(_ request: PanelPreviewImageCache.Request, environment: EnvironmentValues) -> CGImage? {
        let content = PanelPreviewBoard(panel: request.panel, preview: request.preview)
            .frame(width: request.size.width, height: request.size.height)
            // Accessibility values are read-only. Forward the source
            // environment so the offscreen canvas honors those settings too.
            .environment(\.self, environment)
            .environment(\.displayScale, request.scale)
            .environment(\.colorScheme, request.colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = request.scale
        return renderer.cgImage
    }
}
