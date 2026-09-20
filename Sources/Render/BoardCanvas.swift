import SwiftUI

/// Paints a `BoardLayout`.
///
/// One `Canvas` rather than a view per flap: an 85" panel is 45×18 = 810
/// tiles, which is a great deal of view identity for what is really a grid
/// of rounded rectangles. Each distinct (character, color) pair resolves to
/// a `GraphicsContext.ResolvedText` once — about 72 of them — and every tile
/// is then a rect fill plus a cached glyph draw. Steady state is one redraw
/// per frame change, roughly every two seconds.
public struct BoardCanvas: View {

    private let layout: BoardLayout
    private let background: BoardColor
    private let animated: Bool

    public init(layout: BoardLayout, background: BoardColor = .black, animated: Bool = false) {
        self.layout = layout
        self.background = background
        self.animated = animated
    }

    public var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            draw(in: &context)
        }
        .frame(width: layout.width, height: layout.height)
        .background(background.swiftUI)
        // The flip is announced to VoiceOver by the viewer, not per tile:
        // 810 accessibility elements would make the board unusable to browse.
        .accessibilityHidden(true)
        .animation(animated ? .easeInOut(duration: 0.18) : nil, value: layout.tiles.count)
    }

    private func draw(in context: inout GraphicsContext) {
        let font = BoardFont.glyph(size: layout.fontSize)
        let unlit = BoardColor.black.swiftUI
        let ink = Color.white

        // Resolve each distinct glyph once, then stamp it.
        var resolved: [Character: GraphicsContext.ResolvedText] = [:]

        for tile in layout.tiles {
            let rect = CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height)
            let shape = Path(roundedRect: rect, cornerRadius: tile.radius)

            switch tile.cell {
            case .blank:
                context.fill(shape, with: .color(unlit))

            case .color(let color):
                context.fill(shape, with: .color(color.swiftUI))

            case .character(let character):
                context.fill(shape, with: .color(unlit))
                let text: GraphicsContext.ResolvedText
                if let cached = resolved[character] {
                    text = cached
                } else {
                    text = context.resolve(Text(String(character)).font(font).foregroundColor(ink))
                    resolved[character] = text
                }
                let size = text.measure(in: rect.size)
                context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
                _ = size
            }
        }
    }
}
