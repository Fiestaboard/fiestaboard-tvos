import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardTV

@MainActor
final class MatrixTransitionTests: XCTestCase {
    private func request(_ rgb: UInt32, width: Int = 2,
                         presentation: MatrixPresentation = .init(sizing: .fitPanel),
                         height: Int = 1, style: MatrixTransitionStyle = .characterWipe) -> MatrixTransitionFrame {
        MatrixTransitionFrame(raster: MatrixRaster(width: width, height: height,
            pixels: Array(repeating: rgb, count: width * height), text: ""), display: .standard,
            presentation: presentation, drift: .zero, lighting: false, transitionStyle: style)
    }

    private func sample(_ surface: MatrixTransitionSurface, x: Int, y: Int)
        -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard let image = surface.visibleImage() else { return nil }
        // UIImage.size is in points; the sampling helper addresses CGImage pixels.
        return image.pixel(x: Int(CGFloat(x) * image.scale), y: Int(CGFloat(y) * image.scale))
    }

    private func host(size: CGSize = CGSize(width: 100, height: 50)) -> (UIWindow, MatrixTransitionSurface) {
        let surface = MatrixTransitionSurface(frame: CGRect(origin: .zero, size: size))
        let controller = UIViewController()
        controller.view = surface
        let window = UIWindow(frame: surface.frame)
        window.rootViewController = controller
        window.isHidden = false
        surface.layoutIfNeeded()
        return (window, surface)
    }

    private func imageLayers(in layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap { imageLayers(in: $0) }
            + (layer.mask.map { imageLayers(in: $0) } ?? [])
    }

    func testCompositorRevealsCenteredCharacterColumnsWithoutMovingImages() throws {
        for (font, width, boundaries) in [("5x7", 20, [70.0, 130, 200]), ("3x5", 14, [50.0, 90, 140])] {
            let size = CGSize(width: CGFloat(width * 10), height: 100)
            let (window, surface) = host(size: size)
            defer { window.isHidden = true }
            let panel = try MatrixDisplayTests.matrixPanel(width: width, height: 1, font: font)
            func frame(_ rgb: UInt32) -> MatrixTransitionFrame {
                MatrixTransitionFrame(raster: request(rgb, width: width).raster,
                    display: panel.matrixDisplay, presentation: .init(sizing: .fitPanel),
                    drift: .zero, lighting: false)
            }
            surface.update(frame(0xff0000), animated: true)
            surface.update(frame(0x0000ff), animated: true)
            let layers = imageLayers(in: surface.layer)
            guard let mask = layers.first(where: { $0 is CAShapeLayer && $0.animation(forKey: "message") != nil }) else {
                XCTFail("character wipes require a reveal mask, not translated snapshots")
                continue
            }
            let animation = try XCTUnwrap(mask.animation(forKey: "message") as? CAKeyframeAnimation)
            XCTAssertEqual(animation.keyPath, "path")
            XCTAssertEqual(animation.calculationMode, .discrete)
            let paths = try XCTUnwrap(animation.values as? [CGPath])
            XCTAssertEqual(paths.count, 4)
            XCTAssertTrue(try XCTUnwrap(paths.first).isEmpty)
            XCTAssertEqual(paths.dropFirst().map { Double($0.boundingBox.width) }, boundaries,
                           "reveal boundaries follow the centered glyph grid, including outer padding")
            for layer in layers where layer.contents != nil {
                XCTAssertNil(layer.animationKeys(), "physical LED textures never move or fade")
                XCTAssertEqual(layer.frame, CGRect(origin: .zero, size: size))
                XCTAssertEqual(layer.opacity, 1)
            }
        }
    }

    func testWipeRevealsWholeCharacterColumnsFromLeftWithoutBlendingColors() async throws {
        let (window, surface) = host(size: CGSize(width: 576, height: 96))
        defer { window.isHidden = true }
        surface.update(request(0xff0000, width: 48), animated: true)
        surface.update(request(0x0000ff, width: 48), animated: true)
        try await Task.sleep(for: .milliseconds(110))
        let image = try XCTUnwrap(surface.visibleImage())
        var blueColumns = 0
        for column in 0..<48 {
            let pixel = try XCTUnwrap(image.pixel(x: Int(CGFloat(column * 12 + 6) * image.scale),
                                                 y: Int(48 * image.scale)))
            if pixel.b == 255 && pixel.r == 0 { blueColumns += 1 }
            XCTAssertTrue((pixel.r == 255 && pixel.b == 0) || (pixel.b == 255 && pixel.r == 0),
                          "each LED retains an exact old or new color")
            let gap = try XCTUnwrap(image.pixel(x: Int(CGFloat(column * 12) * image.scale),
                                               y: Int(48 * image.scale)))
            XCTAssertEqual(gap.r, 0)
            XCTAssertEqual(gap.b, 0)
        }
        XCTAssertGreaterThan(blueColumns, 0)
        XCTAssertLessThan(blueColumns, 48)
        XCTAssertEqual(blueColumns % 6, 0, "5x7 characters reveal with their one-column spacing")
        XCTAssertEqual(try XCTUnwrap(sample(surface, x: 6, y: 48)).b, 255)
        XCTAssertEqual(try XCTUnwrap(sample(surface, x: 570, y: 48)).r, 255)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(try XCTUnwrap(sample(surface, x: 570, y: 48)).b, 255)
    }

    func testInterruptedWipeKeepsVisibleCharactersAndReachesNewestMessage() async throws {
        let (window, surface) = host(size: CGSize(width: 576, height: 96))
        defer { window.isHidden = true }
        surface.update(request(0xff0000, width: 48), animated: true)
        surface.update(request(0x0000ff, width: 48), animated: true)
        try await Task.sleep(for: .milliseconds(110))
        surface.update(request(0x00ff00, width: 48), animated: true)
        let left = try XCTUnwrap(sample(surface, x: 6, y: 48))
        let right = try XCTUnwrap(sample(surface, x: 570, y: 48))
        XCTAssertEqual(left.b, 255)
        XCTAssertEqual(left.g, 0)
        XCTAssertEqual(right.r, 255)
        XCTAssertEqual(right.g, 0)
        try await Task.sleep(for: .milliseconds(450))
        for x in [6, 282, 570] {
            let final = try XCTUnwrap(sample(surface, x: x, y: 48))
            XCTAssertEqual(final.g, 255)
            XCTAssertEqual(final.r, 0)
            XCTAssertEqual(final.b, 0)
        }
    }

    func testStillAndSettledMessagesReuseTheirPreparedImage() async throws {
        let (window, surface) = host(size: CGSize(width: 192, height: 96))
        defer { window.isHidden = true }
        surface.update(request(0xff0000, width: 16), animated: true)
        let still = try XCTUnwrap(surface.visibleImage())
        XCTAssertTrue(still === surface.visibleImage(), "an idle message needs no composite allocation")
        surface.update(request(0x0000ff, width: 16), animated: true)
        try await Task.sleep(for: .milliseconds(350))
        let settled = try XCTUnwrap(surface.visibleImage())
        XCTAssertTrue(settled === surface.visibleImage(), "a completed wipe reuses its target snapshot")
    }

    func testRowScanRevealsOneStationaryLEDRowAtATime() async throws {
        let (window, surface) = host(size: CGSize(width: 192, height: 288))
        defer { window.isHidden = true }
        surface.update(request(0xff0000, width: 16, height: 24, style: .rowScan), animated: true)
        surface.update(request(0x0000ff, width: 16, height: 24, style: .rowScan), animated: true)
        let mask = try XCTUnwrap(imageLayers(in: surface.layer).first {
            $0 is CAShapeLayer && $0.animation(forKey: "message") != nil
        })
        let animation = try XCTUnwrap(mask.animation(forKey: "message") as? CAKeyframeAnimation)
        let paths = try XCTUnwrap(animation.values as? [CGPath])
        XCTAssertEqual(paths.count, 25)
        XCTAssertEqual(paths.dropFirst().first?.boundingBox.height, 12)
        try await Task.sleep(for: .milliseconds(110))
        XCTAssertEqual(try XCTUnwrap(sample(surface, x: 6, y: 6)).b, 255)
        XCTAssertEqual(try XCTUnwrap(sample(surface, x: 6, y: 282)).r, 255)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(try XCTUnwrap(sample(surface, x: 6, y: 282)).b, 255)
    }

    func testDissolveUsesNativePixelMasksAndPreservesExactLEDColors() async throws {
        let (window, surface) = host(size: CGSize(width: 192, height: 96))
        defer { window.isHidden = true }
        surface.update(request(0xff0000, width: 16, height: 8, style: .pixelDissolve), animated: true)
        surface.update(request(0x0000ff, width: 16, height: 8, style: .pixelDissolve), animated: true)
        let masks = imageLayers(in: surface.layer).compactMap {
            ($0.animation(forKey: "message") as? CAKeyframeAnimation)?.values as? [CGImage]
        }
        let frames = try XCTUnwrap(masks.first, "dissolve masks use native pixel resolution")
        XCTAssertLessThanOrEqual(frames.count, 33)
        XCTAssertTrue(frames.allSatisfy { $0.width == 16 && $0.height == 8 })
        try await Task.sleep(for: .milliseconds(110))
        let image = try XCTUnwrap(surface.visibleImage())
        var blueRows = Set<Int>()
        var blueColumns = Set<Int>()
        var blueCount = 0
        for row in 0..<8 {
            for column in 0..<16 {
                let pixel = try XCTUnwrap(image.pixel(x: Int(CGFloat(column * 12 + 6) * image.scale),
                                                     y: Int(CGFloat(row * 12 + 6) * image.scale)))
                XCTAssertTrue((pixel.r == 255 && pixel.b == 0) || (pixel.b == 255 && pixel.r == 0))
                if pixel.b == 255 {
                    blueCount += 1
                    blueRows.insert(row)
                    blueColumns.insert(column)
                }
            }
        }
        XCTAssertGreaterThan(blueRows.count, 1)
        XCTAssertGreaterThan(blueColumns.count, 1)
        XCTAssertLessThan(blueCount, 128)
    }

    func testMarqueeChangesNativeColorFramesUnderAStationaryLEDMask() async throws {
        let (window, surface) = host(size: CGSize(width: 576, height: 96))
        defer { window.isHidden = true }
        surface.update(request(0xff0000, width: 48, height: 8, style: .marquee), animated: true)
        surface.update(request(0x0000ff, width: 48, height: 8, style: .marquee), animated: true)
        let fields = imageLayers(in: surface.layer).filter {
            ($0.animation(forKey: "message") as? CAKeyframeAnimation)?.keyPath == "position.x"
        }
        XCTAssertEqual(fields.count, 2)
        for field in fields {
            let contents = try XCTUnwrap(field.contents)
            let image = contents as! CGImage
            XCTAssertEqual(image.width, 48, "only a flat native color field moves")
            XCTAssertEqual(image.height, 8)
            let color = try XCTUnwrap(UIImage(cgImage: image).pixel(x: 0, y: 0))
            XCTAssertTrue((color.r == 255 && color.b == 0) || (color.r == 0 && color.b == 255))
            let animation = try XCTUnwrap(field.animation(forKey: "message") as? CAKeyframeAnimation)
            XCTAssertEqual(animation.calculationMode, .discrete)
        }
        let field = try XCTUnwrap(fields.first)
        let group = try XCTUnwrap(field.superlayer)
        let mask = try XCTUnwrap(group.mask)
        XCTAssertNil(mask.animationKeys())
        XCTAssertNil(group.animationKeys())
        XCTAssertEqual(mask.frame, CGRect(origin: .zero, size: group.bounds.size))
        try await Task.sleep(for: .milliseconds(110))
        XCTAssertEqual(try XCTUnwrap(sample(surface, x: 6, y: 6)).r, 255)
        XCTAssertEqual(try XCTUnwrap(sample(surface, x: 570, y: 6)).b, 255)
    }

    func testEveryEffectPreservesAnActiveTransitionForUnchangedPixelsAndCanFinishImmediately() async throws {
        for style in MatrixTransitionStyle.allCases {
            let (window, surface) = host(size: CGSize(width: 576, height: 96))
            defer { window.isHidden = true }
            surface.update(request(0xff0000, width: 48, height: 8, style: style), animated: true)
            let blue = request(0x0000ff, width: 48, height: 8, style: style)
            surface.update(blue, animated: true)
            let animatedLayers = imageLayers(in: surface.layer).filter { $0.animation(forKey: "message") != nil }
            let starts = animatedLayers.map { $0.animation(forKey: "message")!.beginTime }
            XCTAssertFalse(starts.isEmpty, "\(style) should install its native compositor effect")
            surface.update(blue, animated: true)
            XCTAssertEqual(animatedLayers.map { $0.animation(forKey: "message")!.beginTime }, starts)
            surface.update(blue, animated: false)
            XCTAssertEqual(try XCTUnwrap(sample(surface, x: 6, y: 6)).b, 255)
            XCTAssertEqual(try XCTUnwrap(sample(surface, x: 570, y: 90)).b, 255)
            XCTAssertTrue(imageLayers(in: surface.layer).allSatisfy { $0.animationKeys() == nil })
            let settled = try XCTUnwrap(surface.visibleImage())
            XCTAssertTrue(settled === surface.visibleImage())
        }
    }

    func testInterruptedMarqueeRetainsVisibleNativePixelsAndAcceptsNewestMessage() async throws {
        let (window, surface) = host(size: CGSize(width: 576, height: 96))
        defer { window.isHidden = true }
        func state() -> String {
            "bounds=\(surface.bounds) scale=\(surface.traitCollection.displayScale) "
                + imageLayers(in: surface.layer).map {
                    "[\(type(of: $0)) bounds=\($0.bounds) position=\($0.position) "
                        + "animation=\(String(describing: $0.animation(forKey: "message")))]"
                }.joined(separator: " ")
        }
        surface.update(request(0xff0000, width: 48, height: 8, style: .marquee), animated: true)
        surface.update(request(0x0000ff, width: 48, height: 8, style: .marquee), animated: true)
        let initialState = state()
        try await Task.sleep(for: .milliseconds(110))
        let beforeRetarget = state()
        surface.update(request(0x00ff00, width: 48, height: 8, style: .marquee), animated: true)
        // Inspect the outgoing native image captured by retargeting. Sampling
        // visibleImage() twice races the new marquee: after just one 60 Hz
        // step its rightmost pixel is legitimately green, and rendering the
        // first sample can take longer than that on a busy simulator.
        let outgoing = try XCTUnwrap(imageLayers(in: surface.layer).first {
            ($0.animation(forKey: "message") as? CAKeyframeAnimation)?.keyPath == "position.x"
                && $0.position.x < 0
        }, "initial: \(initialState) before: \(beforeRetarget) after: \(state())")
        let retainedContents = try XCTUnwrap(outgoing.contents)
        let retained = retainedContents as! CGImage
        XCTAssertEqual(retained.width, 48)
        XCTAssertEqual(retained.height, 8)
        let retainedImage = UIImage(cgImage: retained)
        XCTAssertEqual(try XCTUnwrap(retainedImage.pixel(x: 0, y: 0)).r, 255)
        XCTAssertEqual(try XCTUnwrap(retainedImage.pixel(x: 47, y: 7)).b, 255)
        try await Task.sleep(for: .milliseconds(850))
        XCTAssertEqual(try XCTUnwrap(sample(surface, x: 6, y: 6)).g, 255)
        XCTAssertEqual(try XCTUnwrap(sample(surface, x: 570, y: 90)).g, 255)
    }

    func testFractionalTrueSizePitchKeepsTheCompositedRoundLEDMaskStationary() async throws {
        let (window, surface) = host(size: RenderHarness.tvSize)
        defer { window.isHidden = true }
        let panel = try MatrixDisplayTests.panel(["render_style": "led_matrix", "device_model_spec": [
            "geometry": ["kind": "pixels", "width": 192, "height": 1],
            "appearance": ["pixelShape": "round"]]])
        func frame(_ rgb: UInt32) -> MatrixTransitionFrame {
            MatrixTransitionFrame(raster: request(rgb, width: 192).raster,
                display: panel.matrixDisplay,
                presentation: .init(sizing: .trueSize, diagonalInches: 55, pitchMillimeters: 5),
                drift: .zero, lighting: false, transitionStyle: .marquee)
        }
        func presentedMask() throws -> [Bool] {
            // Sample the compositor used to preserve an interrupted wipe.
            let image = try XCTUnwrap(surface.visibleImage())
            let cg = try XCTUnwrap(image.cgImage)
            return try (0..<cg.width).map { x in
                let pixel = try XCTUnwrap(image.pixel(x: x, y: Int(540 * image.scale)))
                return max(pixel.r, pixel.g, pixel.b) > 100
            }
        }
        surface.update(frame(0xff0000), animated: true)
        try await Task.sleep(for: .milliseconds(60))
        let still = try presentedMask()
        XCTAssertTrue(still.contains(true), "the compositor must have painted the fixture")
        surface.update(frame(0x0000ff), animated: true)
        try await Task.sleep(for: .milliseconds(100))
        let moving = try presentedMask()
        XCTAssertEqual(zip(still, moving).filter { pair in pair.0 != pair.1 }.count, 0,
                       "changing LED colors must not change the physical dot mask, even at fractional device pitch")
    }

    func testDisablingAnimationFinishesAnActiveWipeImmediately() throws {
        let (_, surface) = host()
        surface.update(request(0xff0000), animated: true)
        surface.update(request(0x0000ff), animated: true)
        surface.update(request(0x0000ff), animated: false)
        let pixel = try XCTUnwrap(sample(surface, x: 25, y: 25))
        XCTAssertEqual(pixel.b, 255)
        XCTAssertEqual(pixel.r, 0)
        XCTAssertTrue(imageLayers(in: surface.layer).allSatisfy { $0.animationKeys()?.isEmpty != false })
    }

    func testReduceMotionShowsNewMessageWithoutWaitingForTheWipe() throws {
        func content(_ rgb: UInt32) -> some View {
            MatrixCanvas(raster: request(rgb).raster, display: .standard, animated: true)
                .environment(\._accessibilityReduceMotion, true)
                .environment(\._accessibilityReduceTransparency, true)
                .frame(width: 100, height: 50)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.black)
                .ignoresSafeArea()
        }
        let host = UIHostingController(rootView: content(0xff0000))
        // The tvOS compositor leaves tiny hosted windows blank; use a full
        // screen with the small fixture anchored at a known pixel position.
        let window = UIWindow(frame: CGRect(origin: .zero, size: RenderHarness.tvSize))
        host.view.frame = window.bounds
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        host.rootView = content(0x0000ff)
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let pixel = try XCTUnwrap(image.pixel(x: 25, y: 25))
        XCTAssertEqual(pixel.b, 255)
        XCTAssertEqual(pixel.r, 0)
    }

    func testGeometryAndPresentationChangesReplaceWithoutWiping() throws {
        let (_, surface) = host()
        surface.update(request(0xff0000), animated: true)
        surface.update(request(0x0000ff, width: 4), animated: true)
        let resized = try XCTUnwrap(sample(surface, x: 12, y: 25))
        XCTAssertEqual(resized.b, 255)
        XCTAssertEqual(resized.r, 0)
        surface.update(request(0x00ff00, width: 4, presentation: .init(sizing: .fillTV)), animated: true)
        let filled = try XCTUnwrap(sample(surface, x: 12, y: 25))
        XCTAssertEqual(filled.g, 255)
        XCTAssertEqual(filled.b, 0)
    }

    func testUnchangedPixelsDoNotRestartOrAllocateAnotherSnapshot() throws {
        let (_, surface) = host()
        surface.update(request(0xff0000), animated: true)
        let layers = imageLayers(in: surface.layer)
        let contents = layers.map { $0.contents as AnyObject? }
        var samePixels = request(0xff0000)
        samePixels.raster = MatrixRaster(width: 2, height: 1, pixels: [0xff0000, 0xff0000], text: "new spoken label")
        surface.update(samePixels, animated: true)
        for (layer, original) in zip(layers, contents) {
            XCTAssertTrue((layer.contents as AnyObject?) === original)
            XCTAssertNil(layer.animationKeys())
        }
    }
}
