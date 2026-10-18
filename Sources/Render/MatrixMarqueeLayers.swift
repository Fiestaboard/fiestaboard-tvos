import SwiftUI
import UIKit

/// Only flat native-resolution color cells move. The alpha mask and lens
/// reflections stay fixed in TV pixels, including at fractional LED pitches.
@MainActor
final class MatrixMarqueeLayers {
    let layer = CALayer()
    private let background = CALayer()
    private let colors = CALayer()
    private let oldColors = CALayer()
    private let newColors = CALayer()
    private let hardware = CALayer()
    private let reflections = CALayer()
    private(set) var isPrepared = false

    init() {
        layer.opacity = 0
        layer.addSublayer(background)
        layer.addSublayer(colors)
        layer.addSublayer(reflections)
        colors.addSublayer(oldColors)
        colors.addSublayer(newColors)
        colors.mask = hardware
        colors.masksToBounds = true
        for field in [oldColors, newColors] {
            field.magnificationFilter = .nearest
            field.minificationFilter = .nearest
        }
    }

    func invalidate() { isPrepared = false }

    func cancel() {
        layer.removeAllAnimations()
        oldColors.removeAllAnimations()
        newColors.removeAllAnimations()
    }

    func prepare(frame: MatrixTransitionFrame, size: CGSize, scale: CGFloat,
                 layout: MatrixLayout, backdrop: UIImage) {
        let source = CGRect(x: layout.originX, y: layout.originY,
                            width: Double(frame.raster.width) * layout.pitch,
                            height: Double(frame.raster.height) * layout.pitch)
        let pitch = CGFloat(layout.pitch)
        let dot = pitch * frame.display.dotRatio
        let inset = (pitch - dot) / 2
        let round = frame.display.appearance?.pixelShape == "round"
        let lighting = frame.lighting && dot >= 3
        func dotRect(_ row: Int, _ column: Int) -> CGRect {
            CGRect(x: source.minX + CGFloat(column) * pitch + inset,
                   y: source.minY + CGFloat(row) * pitch + inset, width: dot, height: dot)
        }
        func shape(_ rect: CGRect) -> Path { round ? Path(ellipseIn: rect) : Path(rect) }
        let maskContent = Canvas { context, _ in
            var dots = Path()
            var outer = Path()
            var inner = Path()
            for row in 0..<frame.raster.height {
                for column in 0..<frame.raster.width {
                    let rect = dotRect(row, column)
                    dots.addPath(shape(rect))
                    if lighting {
                        outer.addPath(shape(rect.insetBy(dx: -pitch * 0.14, dy: -pitch * 0.14)))
                        inner.addPath(shape(rect.insetBy(dx: -pitch * 0.07, dy: -pitch * 0.07)))
                    }
                }
            }
            if lighting {
                context.fill(outer, with: .color(.white.opacity(0.04)))
                context.fill(inner, with: .color(.white.opacity(0.06)))
            }
            context.fill(dots, with: .color(.white))
        }.frame(width: size.width, height: size.height)
        let maskRenderer = ImageRenderer(content: maskContent)
        maskRenderer.scale = scale
        let lensContent = Canvas { context, _ in
            guard lighting else { return }
            context.clip(to: Path(frame.presentation.sizing == .fillTV
                ? CGRect(origin: .zero, size: size) : source))
            for row in layout.rows {
                var dots = Path()
                for column in layout.columns { dots.addPath(shape(dotRect(row, column))) }
                let rect = dotRect(row, 0)
                context.fill(dots, with: .linearGradient(MatrixCanvas.lens,
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            }
        }.frame(width: size.width, height: size.height)
        let lensRenderer = ImageRenderer(content: lensContent)
        lensRenderer.scale = scale
        layer.frame = CGRect(origin: .zero, size: size)
        background.frame = layer.bounds
        background.contents = backdrop.cgImage
        background.contentsScale = scale
        reflections.frame = layer.bounds
        reflections.contents = lensRenderer.cgImage
        reflections.contentsScale = scale
        colors.frame = source
        hardware.frame = colors.bounds
        hardware.contents = maskRenderer.cgImage
        hardware.contentsScale = scale
        hardware.contentsRect = CGRect(x: source.minX / size.width, y: source.minY / size.height,
                                       width: source.width / size.width, height: source.height / size.height)
        for field in [oldColors, newColors] { field.bounds = colors.bounds }
        isPrepared = true
    }

    func start(from: MatrixRaster, to: MatrixRaster, pitch: CGFloat) -> CFTimeInterval {
        oldColors.contents = MatrixPixelFrames.colors(from)
        newColors.contents = MatrixPixelFrames.colors(to)
        let width = colors.bounds.width
        oldColors.position = CGPoint(x: -width / 2, y: colors.bounds.midY)
        newColors.position = CGPoint(x: width / 2, y: colors.bounds.midY)
        let start = CACurrentMediaTime()
        let duration = Double(to.width) / 60
        for (field, offset) in [(oldColors, CGFloat.zero), (newColors, width)] {
            let steps = CAKeyframeAnimation(keyPath: "position.x")
            steps.values = (0...to.width).map { width / 2 + offset - CGFloat($0) * pitch }
            steps.keyTimes = (0...to.width).map { NSNumber(value: Double($0) / Double(to.width)) }
            steps.calculationMode = .discrete
            steps.duration = duration
            steps.beginTime = field.convertTime(start, from: nil)
            field.add(steps, forKey: "message")
        }
        // A binary visibility change restores the exact prepared snapshot at
        // the endpoint. No opacity values between zero and one are emitted.
        let visibility = CAKeyframeAnimation(keyPath: "opacity")
        visibility.values = [1, 0]
        visibility.keyTimes = [0, 1]
        visibility.calculationMode = .discrete
        visibility.duration = duration
        visibility.beginTime = layer.convertTime(start, from: nil)
        layer.add(visibility, forKey: "message")
        return start
    }
}
