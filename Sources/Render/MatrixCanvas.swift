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

        let lens = Self.lens
        for row in layout.rows {
            for col in layout.columns {
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

    private static func color(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}
