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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var transition: BoardFlipTransition?

    private let layout: BoardLayout
    private let background: BoardColor
    private let animated: Bool
    private let code62: Code62Glyph

    public init(layout: BoardLayout, background: BoardColor = .black,
                animated: Bool = false, code62: Code62Glyph = .degree) {
        self.layout = layout
        self.background = background
        self.animated = animated
        self.code62 = code62
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0,
                                paused: transition == nil || !animated || reduceMotion)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                Self.paint(layout, background: background,
                           transition: animated && !reduceMotion ? transition : nil,
                           at: timeline.date, in: &context)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .background(background == .black ? Color.black : background.swiftUI)
        // The flip is announced to VoiceOver by the viewer, not per tile:
        // 810 accessibility elements would make the board unusable to browse.
        .accessibilityHidden(true)
        .onChange(of: layout.tiles.map(\.cell)) { old, new in
            guard animated, !reduceMotion, old.count == new.count else {
                transition = nil
                return
            }
            let now = Date()
            transition = transition?.retargeted(to: new, at: now)
                ?? BoardFlipTransition(from: old, to: new, code62: code62,
                                       startedAt: now)
        }
        .task(id: transition?.startedAt) {
            guard let startedAt = transition?.startedAt else { return }
            try? await Task.sleep(nanoseconds: UInt64((transition?.duration ?? 0) * 1_000_000_000))
            guard !Task.isCancelled, transition?.startedAt == startedAt else { return }
            transition = nil
        }
    }

    static func paint(_ layout: BoardLayout, background: BoardColor,
                      transition: BoardFlipTransition?, at date: Date,
                      in context: inout GraphicsContext) {
        let font = BoardFont.glyph(size: layout.fontSize)
        let whiteHardware = background == .white
        let unlit = whiteHardware ? Color(hex: "#e8e8e8") : Color.black
        let ink = whiteHardware ? Color.black : Color(hex: "#f0f0e8")

        // Resolve each distinct glyph once, then stamp it.
        var resolved: [Character: GraphicsContext.ResolvedText] = [:]

        for (index, tile) in layout.tiles.enumerated() {
            if let sample = transition?.sample(index: index, at: date), sample.isAnimating {
                paintSplit(tile: tile, sample: sample, in: &context, resolved: &resolved,
                           font: font, unlit: unlit, ink: ink, whiteHardware: whiteHardware)
            } else {
                draw(tile: tile, cell: tile.cell, in: &context, resolved: &resolved,
                     font: font, unlit: unlit, ink: ink, whiteHardware: whiteHardware)
            }
            drawSeam(tile: tile, whiteHardware: whiteHardware, in: &context)
        }
    }

    private static func paintSplit(tile: TileRect, sample: BoardFlipTransition.Sample,
                                   in context: inout GraphicsContext,
                                   resolved: inout [Character: GraphicsContext.ResolvedText],
                                   font: Font, unlit: Color, ink: Color, whiteHardware: Bool) {
        let midY = tile.y + tile.height / 2
        let top = CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height / 2)
        let bottom = CGRect(x: tile.x, y: midY, width: tile.width, height: tile.height / 2)

        var newTop = context
        newTop.clip(to: Path(top))
        draw(tile: tile, cell: sample.next, in: &newTop, resolved: &resolved,
             font: font, unlit: unlit, ink: ink, whiteHardware: whiteHardware)

        var oldBottom = context
        oldBottom.clip(to: Path(bottom))
        draw(tile: tile, cell: sample.previous, in: &oldBottom, resolved: &resolved,
             font: font, unlit: unlit, ink: ink, whiteHardware: whiteHardware)

        if sample.progress < 0.5 {
            let t = sample.progress * 2
            let fall = t * t // FiestaUI's ease-in: the top leaf accelerates.
            let scale = max(0.001, cos(.pi / 2 * fall))
            var flap = context
            flap.clip(to: Path(top))
            flap.translateBy(x: 0, y: midY)
            flap.scaleBy(x: 1, y: scale)
            flap.translateBy(x: 0, y: -midY)
            draw(tile: tile, cell: sample.previous, in: &flap, resolved: &resolved,
                 font: font, unlit: unlit, ink: ink, whiteHardware: whiteHardware)
        } else {
            let t = (sample.progress - 0.5) * 2
            let settle = 1 - pow(1 - t, 3) // fast rise, soft landing.
            let scale = max(0.001, sin(.pi / 2 * settle))
            var flap = context
            flap.clip(to: Path(bottom))
            flap.translateBy(x: 0, y: midY)
            flap.scaleBy(x: 1, y: scale)
            flap.translateBy(x: 0, y: -midY)
            draw(tile: tile, cell: sample.next, in: &flap, resolved: &resolved,
                 font: font, unlit: unlit, ink: ink, whiteHardware: whiteHardware)
        }

        let shadow = 0.25 * sin(.pi * sample.progress)
        context.fill(Path(bottom), with: .color(Color.black.opacity(shadow)))
    }

    private static func drawSeam(tile: TileRect, whiteHardware: Bool,
                                 in context: inout GraphicsContext) {
        let midY = tile.y + tile.height / 2
        let gap = CGRect(x: tile.x, y: midY, width: tile.width, height: 1)
        let highlight = CGRect(x: tile.x, y: midY + 1, width: tile.width, height: 1)
        context.fill(Path(gap), with: .color(Color.black.opacity(whiteHardware ? 0.12 : 0.35)))
        context.fill(Path(highlight), with: .color(Color.white.opacity(whiteHardware ? 0.55 : 0.13)))
    }

    private static func draw(tile: TileRect, cell: BoardCell,
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
