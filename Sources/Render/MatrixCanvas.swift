import SwiftUI

/// Square-pitch LEDs, shared by the viewer and panel cards.
struct MatrixCanvas: View {
    static let lens = Gradient(stops: [
        .init(color: .white.opacity(0.10), location: 0),
        .init(color: .clear, location: 0.32),
        .init(color: .clear, location: 0.65),
        .init(color: .black.opacity(0.16), location: 1)
    ])
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let raster: MatrixRaster
    let display: MatrixDisplay
    var presentation: MatrixPresentation = .init(sizing: .fitPanel)
    var drift: BoardOffset = .zero
    var animated: Bool = false
    var transitionStyle: MatrixTransitionStyle = .characterWipe

    var body: some View {
        Group {
            if animated && !reduceMotion {
                MatrixTransitionCanvas(frame: MatrixTransitionFrame(raster: raster, display: display,
                    presentation: presentation, drift: drift,
                    lighting: !reduceTransparency && contrast != .increased,
                    transitionStyle: transitionStyle))
            } else {
                Canvas { context, size in
                    Self.paint(raster, display: display, size: size,
                               lighting: !reduceTransparency && contrast != .increased,
                               presentation: presentation, drift: drift, in: &context)
                }
            }
        }
        .accessibilityHidden(true)
    }

    static func paint(_ raster: MatrixRaster, display: MatrixDisplay, size: CGSize,
                      lighting: Bool, presentation: MatrixPresentation = .init(sizing: .fitPanel),
                      drift: BoardOffset = .zero, in context: inout GraphicsContext) {
        guard let layout = MatrixLayout.make(width: raster.width, height: raster.height,
            viewportWidth: size.width, viewportHeight: size.height, presentation: presentation, drift: drift) else { return }
        let pitch = CGFloat(layout.pitch)
        let origin = CGPoint(x: layout.originX, y: layout.originY)
        let bounds = presentation.sizing == .fillTV ? CGRect(origin: .zero, size: size)
            : CGRect(origin: origin, size: CGSize(width: CGFloat(raster.width) * pitch,
                                                  height: CGFloat(raster.height) * pitch))
        context.clip(to: Path(bounds)) // Light belongs to the panel; the surround stays OLED black.
        context.fill(Path(bounds), with: .color(color(MatrixRaster.hex(display.appearance?.substrateColor) ?? 0)))
        let dot = pitch * display.dotRatio
        let inset = (pitch - dot) / 2
        let off = MatrixRaster.hex(display.appearance?.offColor) ?? 0x1a1a1a
        let round = display.appearance?.pixelShape == "round"
        // Below three points the lens is subpixel detail. Keep dense previews crisp.
        let lightsLens = lighting && dot >= 3
        func rect(_ row: Int, _ col: Int) -> CGRect {
            CGRect(x: origin.x + CGFloat(col) * pitch + inset,
                   y: origin.y + CGFloat(row) * pitch + inset, width: dot, height: dot)
        }
        func shape(_ rect: CGRect) -> Path { round ? Path(ellipseIn: rect) : Path(rect) }

        if lightsLens {
            // Two faint, nested silhouettes approximate a short light falloff.
            // Batch by emitted color: no per-LED blur, layer, or SwiftUI view.
            var outer: [UInt32: Path] = [:]
            var inner: [UInt32: Path] = [:]
            for row in 0..<raster.height {
                for col in 0..<raster.width {
                    let rgb = raster.pixels[row * raster.width + col]
                    guard rgb != 0 else { continue }
                    let lens = rect(row, col)
                    outer[rgb, default: Path()].addPath(shape(lens.insetBy(dx: -pitch * 0.14, dy: -pitch * 0.14)))
                    inner[rgb, default: Path()].addPath(shape(lens.insetBy(dx: -pitch * 0.07, dy: -pitch * 0.07)))
                }
            }
            // Stable order keeps mixed-color overlaps deterministic.
            for rgb in outer.keys.sorted() {
                context.fill(outer[rgb]!, with: .color(color(rgb).opacity(0.04)))
                context.fill(inner[rgb]!, with: .color(color(rgb).opacity(0.06)))
            }
        }

        // A tall matrix can leave hundreds of thousands of unlit LEDs
        // outside its source rectangle. Repeat one LED texture there instead
        // of submitting one path per dot. Source pixels retain the original
        // vector painter, including their subpixel edges and exact colors.
        let sourceBounds = CGRect(origin: origin,
                                  size: CGSize(width: CGFloat(raster.width) * pitch,
                                               height: CGFloat(raster.height) * pitch))
        let useTiledSurround = presentation.sizing == .fillTV && !lightsLens
            && layout.rows.count * layout.columns.count - raster.width * raster.height > 65_536
        let tile = useTiledSurround ? offFieldTile(display: display, pitch: pitch, origin: origin,
                                                       scale: context.environment.displayScale) : nil
        let tiledSurround = tile != nil
        if let tile {
            var surround = context
            surround.clip(to: Path(sourceBounds), options: .inverse)
            surround.fill(Path(bounds), with: .tiledImage(Image(decorative: tile.image, scale: tile.scale).interpolation(.none),
                                                          origin: tile.origin))
        }
        let paintRows = tiledSurround ? 0..<raster.height : layout.rows
        let paintColumns = tiledSurround ? 0..<raster.width : layout.columns
        let lens = Self.lens
        for row in paintRows {
            for col in paintColumns {
                let rgb = row >= 0 && row < raster.height && col >= 0 && col < raster.width
                    ? raster.pixels[row * raster.width + col] : 0
                let rect = rect(row, col)
                let path = shape(rect)
                context.fill(path, with: .color(color(rgb == 0 ? off : rgb)))
                if lightsLens {
                    // A clear middle preserves the model's exact lit and off colors.
                    context.fill(path, with: .linearGradient(lens,
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                }
            }
        }
    }

    /// Repeat a block whose edges land on physical pixels. A one-LED tile
    /// minified to fractional pitch averages away the visible dot pattern.
    /// Baking the drift's fractional phase into this block avoids that blur.
    private static func offFieldTile(display: MatrixDisplay, pitch: CGFloat, origin: CGPoint,
                                     scale: CGFloat) -> (image: CGImage, origin: CGPoint, scale: CGFloat)? {
        let scale = max(1, scale)
        let physicalPitch = pitch * scale
        guard let count = (1...128).first(where: {
            abs(physicalPitch * CGFloat($0) - (physicalPitch * CGFloat($0)).rounded()) < 0.000001
        }) else { return nil }
        let side = Int((physicalPitch * CGFloat(count)).rounded())
        guard side > 0, side <= 512,
              let bitmap = CGContext(data: nil, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        func setColor(_ rgb: UInt32) {
            bitmap.setFillColor(red: CGFloat((rgb >> 16) & 255) / 255,
                                green: CGFloat((rgb >> 8) & 255) / 255,
                                blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
        setColor(MatrixRaster.hex(display.appearance?.substrateColor) ?? 0)
        bitmap.fill(CGRect(x: 0, y: 0, width: side, height: side))
        bitmap.translateBy(x: 0, y: CGFloat(side))
        bitmap.scaleBy(x: 1, y: -1)
        let phaseX = origin.x * scale - floor(origin.x * scale)
        let phaseY = origin.y * scale - floor(origin.y * scale)
        let dot = physicalPitch * display.dotRatio
        let inset = (physicalPitch - dot) / 2
        setColor(MatrixRaster.hex(display.appearance?.offColor) ?? 0x1a1a1a)
        for row in -1...count {
            for col in -1...count {
                let rect = CGRect(x: CGFloat(col) * physicalPitch + phaseX + inset,
                                  y: CGFloat(row) * physicalPitch + phaseY + inset, width: dot, height: dot)
                if display.appearance?.pixelShape == "round" { bitmap.fillEllipse(in: rect) }
                else { bitmap.fill(rect) }
            }
        }
        guard let image = bitmap.makeImage() else { return nil }
        return (image, CGPoint(x: floor(origin.x * scale) / scale,
                               y: floor(origin.y * scale) / scale), scale)
    }

    private static func color(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}
