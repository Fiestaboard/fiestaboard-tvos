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

    @State private var transition: BoardFlipTransition?

    private let layout: BoardLayout
    private let background: BoardColor
    private let animated: Bool

    public init(layout: BoardLayout, background: BoardColor = .black, animated: Bool = false) {
        self.layout = layout
        self.background = background
        self.animated = animated
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0,
                                paused: transition == nil || !animated)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                draw(in: &context, at: timeline.date)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .background(background == .black ? Color.black : background.swiftUI)
        // The flip is announced to VoiceOver by the viewer, not per tile:
        // 810 accessibility elements would make the board unusable to browse.
        .accessibilityHidden(true)
        .onChange(of: layout.tiles.map(\.cell)) { old, new in
            guard animated, old.count == new.count else {
                transition = nil
                return
            }
            let columns = (layout.tiles.map(\.col).max() ?? -1) + 1
            transition = BoardFlipTransition(from: old, to: new, columns: columns,
                                             startedAt: Date())
        }
        .task(id: transition?.startedAt) {
            guard let startedAt = transition?.startedAt else { return }
            try? await Task.sleep(nanoseconds: UInt64(BoardFlipTransition.totalDuration * 1_000_000_000))
            guard !Task.isCancelled, transition?.startedAt == startedAt else { return }
            transition = nil
        }
    }

    private func draw(in context: inout GraphicsContext, at date: Date) {
        let font = BoardFont.glyph(size: layout.fontSize)
        let whiteHardware = background == .white
        let unlit = whiteHardware ? Color(hex: "#e8e8e8") : Color.black
        let ink = whiteHardware ? Color.black : Color.white

        // Resolve each distinct glyph once, then stamp it.
        var resolved: [Character: GraphicsContext.ResolvedText] = [:]

        for (index, tile) in layout.tiles.enumerated() {
            let sample = animated ? transition?.sample(index: index, at: date) : nil
            let cell = sample?.cell ?? tile.cell
            if let scale = sample?.scaleY, scale < 0.999 {
                context.drawLayer { layer in
                    let midY = tile.y + tile.height / 2
                    layer.translateBy(x: 0, y: midY)
                    layer.scaleBy(x: 1, y: scale)
                    layer.translateBy(x: 0, y: -midY)
                    draw(tile: tile, cell: cell, in: &layer, resolved: &resolved,
                         font: font, unlit: unlit, ink: ink, whiteHardware: whiteHardware)
                }
            } else {
                draw(tile: tile, cell: cell, in: &context, resolved: &resolved,
                     font: font, unlit: unlit, ink: ink, whiteHardware: whiteHardware)
            }
        }
    }

    private func draw(tile: TileRect, cell: BoardCell,
                      in context: inout GraphicsContext,
                      resolved: inout [Character: GraphicsContext.ResolvedText],
                      font: Font, unlit: Color, ink: Color, whiteHardware: Bool) {
        let rect = CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height)
        let shape = Path(roundedRect: rect, cornerRadius: tile.radius)

        switch cell {
            case .blank:
                context.fill(shape, with: .color(unlit))

            case .color(let color):
                let pigment: BoardColor
                if whiteHardware && color == .white { pigment = .black }
                else if whiteHardware && color == .black { pigment = .white }
                else { pigment = color }
                context.fill(shape, with: .color(pigment == .black ? .black : pigment.swiftUI))

            case .character(let character):
                context.fill(shape, with: .color(unlit))
                let text: GraphicsContext.ResolvedText
                if let cached = resolved[character] {
                    text = cached
                } else {
                    text = context.resolve(Text(String(character)).font(font).foregroundColor(ink))
                    resolved[character] = text
                }
                context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }
}
