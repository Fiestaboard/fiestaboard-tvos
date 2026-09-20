import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardTV

/// Hosts a SwiftUI view off-screen and forces a layout pass so its `body`
/// actually executes — line coverage on view code without UI automation —
/// and can snapshot it so geometry can be asserted by sampling pixels.
@MainActor
enum RenderHarness {

    nonisolated static let tvSize = CGSize(width: 1920, height: 1080)

    static func render<V: View>(_ view: V, size: CGSize = tvSize) {
        let host = UIHostingController(rootView: view.ignoresSafeArea())
        host.view.frame = CGRect(origin: .zero, size: size)
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        window.isHidden = true
        window.rootViewController = nil
    }

    /// Draw `view` into an image so a test can sample what was painted.
    static func image<V: View>(_ view: V, size: CGSize = tvSize) -> UIImage {
        let host = UIHostingController(rootView: view.ignoresSafeArea())
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .clear
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }
}

extension UIImage {
    /// sRGB components at a point, for geometry assertions.
    func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard let cg = cgImage, x >= 0, y >= 0, x < cg.width, y < cg.height else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixel, width: 1, height: 1,
                                      bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: -CGFloat(x), y: -CGFloat(cg.height - y - 1),
                                    width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }
}
