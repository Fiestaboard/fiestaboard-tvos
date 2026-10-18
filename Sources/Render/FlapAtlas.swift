import SwiftUI

/// Pre-render the drum's moving faces once per geometry/appearance. Playback
/// stamps textures instead of rebuilding thousands of clipped vector leaves.
/// Twelve phases per 80 ms step bound phase error to 3.4 ms at a 60 Hz display.
final class FlapAtlas {
    struct Key: Equatable {
        let tileHeight: Double
        let background: BoardColor
        let code62: Code62Glyph
        let scale: Double
    }
    static let phases = 12
    let key: Key
    let verticalPadding = 2.0
    let padding: Double
    let stride: Double
    let height: Double
    let byteCount: Int
    let maximumTextureDimension: Int
    private let images: [CGImage]

    @MainActor
    init?(tileHeight: Double, background: BoardColor, code62: Code62Glyph, scale: Double) {
        guard tileHeight.isFinite, tileHeight > 0, tileHeight <= 120 else { return nil }
        key = Key(tileHeight: tileHeight, background: background, code62: code62, scale: scale)
        padding = ceil(tileHeight * BoardGeometry.tileWidthRatio * 0.1) + 1
        let requestedStride = ceil(tileHeight * BoardGeometry.tileWidthRatio + padding * 2)
        let requestedHeight = ceil(tileHeight) + verticalPadding * 2
        let width = requestedStride * 72
        let totalHeight = requestedHeight * Double(Self.phases + 1)
        // Include transparent padding and round each cell to integral pixels.
        let requestedScale = min(2, max(1, scale))
        let renderScale = min(requestedScale, sqrt(Double(60 * 1024 * 1024) / (width * totalHeight * 4)))
        let cellWidth = ceil(requestedStride * renderScale)
        let cellHeight = ceil(requestedHeight * renderScale)
        let actualStride = cellWidth / renderScale
        let actualHeight = cellHeight / renderScale
        stride = actualStride
        height = actualHeight
        let pad = padding
        let topPad = verticalPadding
        // Keep every backing texture small. One 72-code sheet can exceed
        // the renderer's usable width at Retina scale and produce blank faces.
        // Three sheets retain the same resolution and total memory budget.
        var faces = Array<CGImage?>(repeating: nil, count: 72 * (Self.phases + 1))
        var bytes = 0
        var maximumDimension = 0
        for group in 0..<3 {
            let content = Canvas { context, _ in
                for phase in 0...Self.phases {
                    for column in 0..<24 {
                        let code = group * 24 + column
                        let tile = TileRect(row: phase, col: code,
                            x: Double(column) * actualStride + pad, y: Double(phase) * actualHeight + topPad,
                            width: tileHeight * BoardGeometry.tileWidthRatio, height: tileHeight,
                            radius: tileHeight * BoardGeometry.tileRadiusRatio,
                            cell: BoardTables.cell(forCode: code, code62: code62))
                        BoardCanvas.paintPreparedFace(tile, code: code,
                            progress: phase == Self.phases ? nil : Double(phase) / Double(Self.phases),
                            background: background, code62: code62, in: &context)
                    }
                }
            }.frame(width: actualStride * 24, height: actualHeight * Double(Self.phases + 1))
            let renderer = ImageRenderer(content: content)
            renderer.scale = renderScale
            guard let sheet = renderer.cgImage else { return nil }
            bytes += sheet.bytesPerRow * sheet.height
            maximumDimension = max(maximumDimension, sheet.width, sheet.height)
            for phase in 0...Self.phases {
                for column in 0..<24 {
                    guard let face = sheet.cropping(to: CGRect(x: Double(column) * cellWidth,
                        y: Double(phase) * cellHeight, width: cellWidth, height: cellHeight)) else { return nil }
                    faces[phase * 72 + group * 24 + column] = face
                }
            }
        }
        byteCount = bytes
        maximumTextureDimension = maximumDimension
        images = faces.compactMap { $0 }
    }

    func image(code: Int, phase: Int?) -> CGImage? {
        let phase = phase ?? Self.phases
        guard (0..<72).contains(code), (0...Self.phases).contains(phase) else { return nil }
        return images[phase * 72 + code]
    }

    func paint(_ layout: BoardLayout, transition: BoardFlipTransition?, at date: Date,
               in context: inout GraphicsContext) {
        var resolved: [Int: GraphicsContext.ResolvedImage] = [:]
        for (index, tile) in layout.tiles.enumerated() {
            let sample = transition?.sample(index: index, at: date)
            let active = sample?.isAnimating == true
            var code = active ? sample!.drumCode! : BoardTables.code(for: tile.cell)
            let phase = active ? min(Self.phases, Int((sample!.progress * Double(Self.phases)).rounded())) : Self.phases
            if active && phase == Self.phases { code = (code + 1) % 72 }
            let id = phase * 72 + code
            let face: GraphicsContext.ResolvedImage
            if let cached = resolved[id] { face = cached }
            else {
                face = context.resolve(Image(decorative: images[id], scale: 1))
                resolved[id] = face
            }
            context.draw(face, in: CGRect(x: tile.x - padding, y: tile.y - verticalPadding, width: stride, height: height))
        }
    }
}
