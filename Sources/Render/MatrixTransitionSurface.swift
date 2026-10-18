import SwiftUI
import UIKit

/// Everything that affects a snapshot. Spoken labels alone do not repaint LEDs.
struct MatrixTransitionFrame: Equatable {
    var raster: MatrixRaster
    let display: MatrixDisplay
    let presentation: MatrixPresentation
    let drift: BoardOffset
    let lighting: Bool
    var transitionStyle: MatrixTransitionStyle = .characterWipe

    func hasSameGeometry(as other: Self) -> Bool {
        raster.width == other.raster.width && raster.height == other.raster.height
            && display == other.display && presentation == other.presentation
            && drift == other.drift && lighting == other.lighting
            && transitionStyle == other.transitionStyle
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hasSameGeometry(as: rhs) && lhs.raster.pixels == rhs.raster.pixels
    }
}

struct MatrixTransitionCanvas: UIViewRepresentable {
    let frame: MatrixTransitionFrame

    func makeUIView(context: Context) -> MatrixTransitionSurface {
        MatrixTransitionSurface(frame: .zero)
    }

    func updateUIView(_ view: MatrixTransitionSurface, context: Context) {
        view.update(frame, animated: true)
    }
}

/// Discrete hardware effects run in Core Animation. The physical LED grid
/// remains fixed; no effect blends old and new message colors.
@MainActor
final class MatrixTransitionSurface: UIView {
    private let previous = CALayer()
    private let incoming = CALayer()
    private let reveal = CAShapeLayer()
    private let dissolveMask = CALayer()
    private let dissolveField = CALayer()
    private let dissolveOutside = CAShapeLayer()
    private let marquee = MatrixMarqueeLayers()
    private var previousImage: UIImage?
    private var incomingImage: UIImage?
    private var requested: MatrixTransitionFrame?
    private var rendered: MatrixTransitionFrame?
    private var renderedSize: CGSize = .zero
    private var renderedScale: CGFloat = 0
    private var rectangles: [CGRect] = []
    private var dissolveFrames: [CGImage] = []
    private var sourceRect: CGRect = .zero
    private var marqueeFrom: MatrixRaster?
    private var allowsAnimation = false
    private var startedAt: CFTimeInterval?
    private var secondsPerStep: Double = 0.05
    private var stepCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        clipsToBounds = true
        isUserInteractionEnabled = false
        layer.addSublayer(previous)
        layer.addSublayer(incoming)
        layer.addSublayer(marquee.layer)
        incoming.mask = reveal
        reveal.fillColor = UIColor.white.cgColor
        dissolveMask.addSublayer(dissolveField)
        dissolveMask.addSublayer(dissolveOutside)
        dissolveField.magnificationFilter = .nearest
        dissolveField.minificationFilter = .nearest
        dissolveOutside.fillColor = UIColor.white.cgColor
        dissolveOutside.fillRule = .evenOdd
    }

    required init?(coder: NSCoder) { return nil }

    func update(_ frame: MatrixTransitionFrame, animated: Bool) {
        requested = frame
        allowsAnimation = animated
        renderIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderIfNeeded()
    }

    private func cancelAnimations() {
        reveal.removeAllAnimations()
        dissolveField.removeAllAnimations()
        dissolveOutside.removeAllAnimations()
        marquee.cancel()
        startedAt = nil
        previous.contents = nil
        previousImage = nil
        marqueeFrom = nil
    }

    private func renderIfNeeded() {
        guard let requested, bounds.width > 0, bounds.height > 0,
              let layout = MatrixLayout.make(width: requested.raster.width, height: requested.raster.height,
                  viewportWidth: bounds.width, viewportHeight: bounds.height,
                  presentation: requested.presentation, drift: requested.drift) else { return }
        let scale = max(1, traitCollection.displayScale)
        let sameGeometry = rendered?.hasSameGeometry(as: requested) == true
            && renderedSize == bounds.size && renderedScale == scale
        if sameGeometry && rendered == requested {
            if !allowsAnimation {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                cancelAnimations()
                CATransaction.commit()
            }
            return
        }
        #if DEBUG
        let began = CACurrentMediaTime()
        #endif
        let size = bounds.size
        let viewport = CGRect(origin: .zero, size: size)
        let source = CGRect(x: layout.originX, y: layout.originY,
                            width: Double(requested.raster.width) * layout.pitch,
                            height: Double(requested.raster.height) * layout.pitch)
        guard let image = snapshot(requested.raster, frame: requested, size: size, scale: scale) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !sameGeometry { marquee.invalidate() }
        if requested.transitionStyle == .marquee && !marquee.isPrepared {
            let blank = MatrixRaster(width: requested.raster.width, height: requested.raster.height,
                pixels: Array(repeating: 0, count: requested.raster.pixels.count), text: "")
            if let backdrop = snapshot(blank, frame: requested, size: size, scale: scale, lighting: false) {
                marquee.prepare(frame: requested, size: size, scale: scale, layout: layout, backdrop: backdrop)
            }
        }
        // Capture after preparation so retargeting never rewinds playback.
        let shouldAnimate = sameGeometry && allowsAnimation
        let fromRaster = shouldAnimate && requested.transitionStyle == .marquee ? visibleRaster() : nil
        let fromImage = shouldAnimate && requested.transitionStyle != .marquee ? visibleImage() : nil
        cancelAnimations()
        for imageLayer in [previous, incoming] {
            imageLayer.frame = viewport
            imageLayer.contentsScale = scale
        }
        reveal.frame = viewport
        reveal.contentsScale = scale
        reveal.path = CGPath(rect: viewport, transform: nil)
        incoming.mask = reveal
        previousImage = fromImage
        previous.contents = fromImage?.cgImage
        incomingImage = image
        incoming.contents = image.cgImage
        sourceRect = source
        rectangles = []
        if !sameGeometry { dissolveFrames = [] }
        switch requested.transitionStyle {
        case .characterWipe:
            rectangles = MatrixRaster.characterColumnBoundaries(width: requested.raster.width,
                font: requested.display.font).map { column in
                    let width = column == requested.raster.width ? size.width
                        : min(size.width, max(0, layout.originX + Double(column) * layout.pitch))
                    return CGRect(x: 0, y: 0, width: width, height: size.height)
                }
            secondsPerStep = 0.05
        case .rowScan:
            rectangles = (1...requested.raster.height).map { row in
                let height = row == requested.raster.height ? size.height
                    : min(size.height, max(0, layout.originY + Double(row) * layout.pitch))
                return CGRect(x: 0, y: 0, width: size.width, height: height)
            }
            secondsPerStep = 1.0 / 60
        case .pixelDissolve:
            if dissolveFrames.isEmpty {
                dissolveFrames = MatrixPixelFrames.dissolve(width: requested.raster.width,
                                                             height: requested.raster.height)
            }
            secondsPerStep = 1.6 / Double(max(1, dissolveFrames.count - 1))
        case .marquee:
            secondsPerStep = 1.0 / 60
        }
        stepCount = requested.transitionStyle == .marquee ? requested.raster.width
            : requested.transitionStyle == .pixelDissolve ? max(0, dissolveFrames.count - 1) : rectangles.count
        if let fromRaster {
            marqueeFrom = fromRaster
            startedAt = marquee.start(from: fromRaster, to: requested.raster, pitch: layout.pitch)
        } else if fromImage != nil && stepCount > 0 {
            let start = CACurrentMediaTime()
            startedAt = start
            if requested.transitionStyle == .pixelDissolve {
                dissolveMask.frame = viewport
                dissolveField.frame = source
                dissolveField.contents = dissolveFrames.last
                let outside = CGMutablePath()
                outside.addRect(viewport)
                outside.addRect(source)
                dissolveOutside.frame = viewport
                dissolveOutside.path = outside
                dissolveOutside.opacity = 1
                incoming.mask = dissolveMask
                animate(dissolveField, keyPath: "contents", values: dissolveFrames, start: start)
                // The area beyond the source panel changes at the endpoint.
                animate(dissolveOutside, keyPath: "opacity",
                        values: Array(repeating: 0, count: stepCount) + [1], start: start)
            } else {
                animate(reveal, keyPath: "path", values: [CGMutablePath()] + rectangles.map {
                    CGPath(rect: $0, transform: nil)
                }, start: start)
            }
        }
        CATransaction.commit()
        rendered = requested
        renderedSize = size
        renderedScale = scale
        #if DEBUG
        MatrixPreparationProbe.record(milliseconds: (CACurrentMediaTime() - began) * 1000,
                                      size: size, scale: scale, raster: requested.raster)
        #endif
    }

    private func animate(_ target: CALayer, keyPath: String, values: [Any], start: CFTimeInterval) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = (0...stepCount).map { NSNumber(value: Double($0) / Double(stepCount)) }
        animation.duration = Double(stepCount) * secondsPerStep
        animation.beginTime = target.convertTime(start, from: nil)
        animation.calculationMode = .discrete
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        target.add(animation, forKey: "message")
    }

    private func snapshot(_ raster: MatrixRaster, frame: MatrixTransitionFrame,
                          size: CGSize, scale: CGFloat, lighting: Bool? = nil) -> UIImage? {
        let content = Canvas { context, _ in
            MatrixCanvas.paint(raster, display: frame.display, size: size,
                lighting: lighting ?? frame.lighting, presentation: frame.presentation,
                drift: frame.drift, in: &context)
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private var currentStep: Int {
        guard let startedAt else { return stepCount }
        return min(stepCount, max(0, Int((CACurrentMediaTime() - startedAt) / secondsPerStep)))
    }

    private func visibleRaster() -> MatrixRaster? {
        guard let raster = rendered?.raster else { return nil }
        if let marqueeFrom, currentStep < stepCount {
            return MatrixRaster(width: raster.width, height: raster.height,
                pixels: MatrixPixelFrames.shifted(marqueeFrom.pixels, raster.pixels,
                    width: raster.width, height: raster.height, step: currentStep), text: raster.text)
        }
        return raster
    }

    /// Only interrupted reveals need a TV-sized composite. Idle and completed
    /// messages return the exact cached image; marquee retargets native pixels.
    func visibleImage() -> UIImage? {
        guard let incomingImage else { return nil }
        let step = currentStep
        guard startedAt != nil, step < stepCount else { return incomingImage }
        if let rendered, rendered.transitionStyle == .marquee, let raster = visibleRaster() {
            return snapshot(raster, frame: rendered, size: renderedSize, scale: renderedScale)
        }
        guard let previousImage else { return incomingImage }
        guard step > 0 else { return previousImage }
        let clipping = CGMutablePath()
        if rendered?.transitionStyle == .pixelDissolve {
            let mask = dissolveFrames[step]
            if let data = mask.dataProvider?.data, let pixels = CFDataGetBytePtr(data) {
                let pitchX = sourceRect.width / CGFloat(mask.width)
                let pitchY = sourceRect.height / CGFloat(mask.height)
                for row in 0..<mask.height {
                    for column in 0..<mask.width where pixels[row * mask.bytesPerRow + column * 4 + 3] != 0 {
                        clipping.addRect(CGRect(x: sourceRect.minX + CGFloat(column) * pitchX,
                            y: sourceRect.minY + CGFloat(row) * pitchY, width: pitchX, height: pitchY))
                    }
                }
            }
        } else {
            clipping.addRect(rectangles[step - 1])
        }
        let viewport = renderedSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = incomingImage.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: viewport, format: format).image { renderer in
            let rect = CGRect(origin: .zero, size: viewport)
            previousImage.draw(in: rect)
            renderer.cgContext.setShouldAntialias(false)
            renderer.cgContext.addPath(clipping)
            renderer.cgContext.clip()
            incomingImage.draw(in: rect)
        }
    }
}

#if DEBUG
/// Opt-in debug measurements; normal playback performs no diagnostic I/O.
@MainActor
private enum MatrixPreparationProbe {
    private static var samples: [[String: Double]] = []

    static func record(milliseconds: Double, size: CGSize, scale: CGFloat, raster: MatrixRaster) {
        guard UserDefaults.standard.bool(forKey: "fiestaboard.renderProfile") else { return }
        samples.append(["milliseconds": milliseconds, "width": size.width, "height": size.height,
                        "scale": scale, "rasterWidth": Double(raster.width), "rasterHeight": Double(raster.height)])
        if samples.count > 100 { samples.removeFirst() }
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: ["samples": samples]) else { return }
        DispatchQueue.global(qos: .utility).async {
            try? data.write(to: directory.appendingPathComponent("matrix-preparation.json"), options: .atomic)
        }
    }
}
#endif
