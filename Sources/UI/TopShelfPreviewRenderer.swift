import SwiftUI

/// The poster Apple TV Home shows for a panel.
///
/// Deliberately the brand mark rather than a picture of the board. A board
/// preview is a black rectangle of small white text: on a Home screen, next
/// to everything else Apple TV shows there, it reads as a screenshot someone
/// pasted in rather than as an app. The panel's name is carried by the
/// carousel item itself, so the art needs no text of its own.
@MainActor
enum TopShelfPreviewRenderer {
    static let size = CGSize(width: 1920, height: 1080)

    /// Rendered once and shared by every item: the poster does not vary by
    /// panel, so there is nothing to recompute per panel — and nothing to
    /// fetch, which is what took a round trip per panel off every load of
    /// the panel list.
    static let poster: Data? = {
        let content = ZStack {
            Fiesta.Colors.brand
            TacoMarkView().padding(size.height * 0.16)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }()
}
