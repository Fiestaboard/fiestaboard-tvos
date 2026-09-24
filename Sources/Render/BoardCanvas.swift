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
        let seam = seam(forTileHeight: layout.tileHeight)

        for (index, tile) in layout.tiles.enumerated() {
            if let sample = transition?.sample(index: index, at: date), sample.isAnimating {
                paintSplit(tile: tile, sample: sample, in: &context, resolved: &resolved,
                           font: font, unlit: unlit, ink: ink, whiteHardware: whiteHardware)
            } else {
                draw(tile: tile, cell: tile.cell, in: &context, resolved: &resolved,
                     font: font, unlit: unlit, ink: ink, whiteHardware: whiteHardware)
            }
            drawSeam(tile: tile, seam: seam, whiteHardware: whiteHardware, in: &context)
        }
    }

    /// One drum step of one tile: a leaf hinged on the axle through the
    /// tile's middle falls forward off the top half, passes edge-on, and
    /// lands on the bottom half showing its other face. `FlapPhysics`
    /// decides where the leaf is, how it projects and how it is lit; this
    /// only paints. Everything is affine fills and cached glyphs — no
    /// gradients, layers or filters — so the cost per animating tile stays
    /// in the same class as a static one.
    private static func paintSplit(tile: TileRect, sample: BoardFlipTransition.Sample,
                                   in context: inout GraphicsContext,
                                   resolved: inout [Character: GraphicsContext.ResolvedText],
                                   font: Font, unlit: Color, ink: Color, whiteHardware: Bool) {
        let midX = tile.x + tile.width / 2
        let midY = tile.y + tile.height / 2
        let halfHeight = tile.height / 2
        let top = CGRect(x: tile.x, y: tile.y, width: tile.width, height: halfHeight)
        let bottom = CGRect(x: tile.x, y: midY, width: tile.width, height: halfHeight)

        let angle = FlapPhysics.angle(at: sample.progress)
        let projection = FlapPhysics.projection(angle: angle)
        let shadow = FlapPhysics.castShadow(angle: angle)
        let brightness = FlapPhysics.brightness(angle: angle)
        let showsNext = angle >= .pi / 2

        // The next leaf, already waiting on the drum behind the falling one.
        var newTop = context
        newTop.clip(to: Path(top))
        draw(tile: tile, cell: sample.next, in: &newTop, resolved: &resolved,
             font: font, unlit: unlit, ink: ink, whiteHardware: whiteHardware)

        // The old bottom stays until the leaf lands on it, with the leaf's
        // shadow sweeping down it: two flat bands, darker under the hinge.
        var oldBottom = context
        oldBottom.clip(to: Path(bottom))
        draw(tile: tile, cell: sample.previous, in: &oldBottom, resolved: &resolved,
             font: font, unlit: unlit, ink: ink, whiteHardware: whiteHardware)
        if shadow.opacity > 0 {
            let face = CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height)
            oldBottom.clip(to: Path(roundedRect: face, cornerRadius: tile.radius))
            let depth = halfHeight * shadow.depth
            oldBottom.fill(Path(CGRect(x: tile.x, y: midY, width: tile.width, height: depth)),
                           with: .color(Color.black.opacity(shadow.opacity * 0.6)))
            oldBottom.fill(Path(CGRect(x: tile.x, y: midY, width: tile.width, height: depth * 0.4)),
                           with: .color(Color.black.opacity(shadow.opacity * 0.5)))
        }

        // The leaf. Below half a pixel it is edge-on and there is nothing
        // to see; skipping it is also what keeps the scale non-singular.
        let leafHeight = halfHeight * projection.height
        guard leafHeight >= 0.5 else { return }
        let outline = leafOutline(tile: tile, midX: midX, midY: midY, height: leafHeight,
                                  widthFactor: projection.widthFactor, hangsBelow: showsNext)

        // Perspective: the face is scaled to its projected height about the
        // hinge and to its near-edge width about the tile's centre line, then
        // clipped to the trapezoid the leaf actually projects to. The hinge
        // edge is exact; the interior differs from a true projective map by
        // under a pixel at board scale.
        var leaf = context
        leaf.clip(to: outline)
        leaf.translateBy(x: midX, y: midY)
        leaf.scaleBy(x: projection.widthFactor, y: projection.height)
        leaf.translateBy(x: -midX, y: -midY)
        draw(tile: tile, cell: showsNext ? sample.next : sample.previous, in: &leaf,
             resolved: &resolved, font: font, unlit: unlit, ink: ink, whiteHardware: whiteHardware)

        // Lighting: the face turns out of the room light as it falls and
        // comes back into it as it lands.
        if brightness < 1 {
            context.fill(outline, with: .color(Color.black.opacity(1 - brightness)))
        }
    }

    /// The silhouette of a leaf swung toward the eye: full tile width along
    /// the hinge, `widthFactor` wider along the free edge, with the tile's
    /// rounded corners carried onto the free edge. Serves as both the clip
    /// for the face and the shape the lighting is applied to.
    private static func leafOutline(tile: TileRect, midX: Double, midY: Double, height: Double,
                                    widthFactor: Double, hangsBelow: Bool) -> Path {
        let direction: Double = hangsBelow ? 1 : -1
        let hingeHalf = tile.width / 2
        let freeHalf = hingeHalf * widthFactor
        let freeY = midY + direction * height
        let rx = min(tile.radius * widthFactor, freeHalf)
        let ry = min(tile.radius * height / (tile.height / 2), height)

        var path = Path()
        path.move(to: CGPoint(x: midX - hingeHalf, y: midY))
        path.addLine(to: CGPoint(x: midX - freeHalf, y: freeY - direction * ry))
        path.addQuadCurve(to: CGPoint(x: midX - freeHalf + rx, y: freeY),
                          control: CGPoint(x: midX - freeHalf, y: freeY))
        path.addLine(to: CGPoint(x: midX + freeHalf - rx, y: freeY))
        path.addQuadCurve(to: CGPoint(x: midX + freeHalf, y: freeY - direction * ry),
                          control: CGPoint(x: midX + freeHalf, y: freeY))
        path.addLine(to: CGPoint(x: midX + hingeHalf, y: midY))
        path.closeSubpath()
        return path
    }

    /// The split between the two leaves: a dark gap with the lit top edge
    /// of the lower leaf under it.
    struct Seam: Equatable {
        /// Height of each of the two lines, in points.
        let thickness: Double
        /// Multiplier on the lines' opacity, 0…1.
        let ink: Double
    }

    /// Each seam line as a fraction of the tile: 2.5% of the height for the
    /// pair, which is a hairline at viewer size (about 1px on a 75pt flap).
    static let seamRatio = 1.0 / 80

    /// The seam is a physical gap and scales with the tile like the glyph
    /// and the corner radius do. Below a pixel it cannot get thinner, so
    /// its opacity carries the scaling instead — a fixed 2px of seam on a
    /// 19pt preview tile weighs as much as the text and reads as striping.
    /// The ink floor keeps a trace of the split on any tile at all.
    static func seam(forTileHeight height: Double) -> Seam {
        let line = height * seamRatio
        let thickness = max(1, line)
        return Seam(thickness: thickness, ink: max(0.3, min(1, line / thickness)))
    }

    private static func drawSeam(tile: TileRect, seam: Seam, whiteHardware: Bool,
                                 in context: inout GraphicsContext) {
        // Snapped to the pixel grid (Apple TV is 1×) so a one-pixel seam
        // lands on one row rather than smearing faintly across two.
        let top = (tile.y + tile.height / 2).rounded()
        let gap = CGRect(x: tile.x, y: top, width: tile.width, height: seam.thickness)
        let highlight = CGRect(x: tile.x, y: top + seam.thickness,
                               width: tile.width, height: seam.thickness)
        context.fill(Path(gap), with: .color(Color.black.opacity((whiteHardware ? 0.12 : 0.35) * seam.ink)))
        context.fill(Path(highlight), with: .color(Color.white.opacity((whiteHardware ? 0.55 : 0.13) * seam.ink)))
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
