import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardTV

/// Regression snapshots for the D7 parity method (PHASE-4-TV-PLAN §2.1).
///
/// Every shot is one Apple TV screen: 1920×1080 pt at scale 2, so the PNG is
/// 3840×2160 px — the same grid as a REST `scale=2` export of a Figma Screen
/// slot. Dark appearance, as the app forces. Rendering is our own
/// `drawHierarchy` pass (the one `RenderHarness` already trusts for the
/// board's `Canvas`); swift-snapshot-testing owns the comparison, the
/// recording and the failure diff.
///
/// `drawHierarchy` does not run the window server's compositor, so glass and
/// the focus platter are NOT captured faithfully here. Those states are shot
/// by XCUITest (`ParityShotsUITests`) through `XCUIScreen`.
///
/// Goldens live in `Tests/__Snapshots__/tvOS<major>/<TestClass>/`. They are
/// split by simulator OS major because system fonts and controls re-render
/// between majors; CI (macos-26) and a newer local Xcode each check against
/// their own set. A missing golden is recorded and the test fails once, the
/// library's default.
@MainActor
enum TVSnapshot {
    static let size = CGSize(width: 1920, height: 1080)
    static let scale: CGFloat = 2

    /// Repository root, from this file's path (`Tests/Support/Snapshot.swift`).
    nonisolated static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    nonisolated static var osMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

    /// Lay `view` out in a real 1920×1080 window and draw it at scale 2.
    static func image<V: View>(_ view: V, settle: TimeInterval = 0.1) -> UIImage {
        let host = UIHostingController(rootView: view
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
            .ignoresSafeArea())
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .black
        let window = UIWindow(frame: host.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }

    /// Compare against the golden for this OS major. Perceptual precision
    /// absorbs glyph anti-aliasing noise; a moved or recoloured element
    /// still fails.
    static func assertMatches(_ image: UIImage, named name: String,
                              file: StaticString = #filePath, testName: String = #function,
                              line: UInt = #line) {
        let testClass = URL(fileURLWithPath: "\(file)").deletingPathExtension().lastPathComponent
        let directory = repoRoot
            .appendingPathComponent("Tests/__Snapshots__/tvOS\(osMajor)/\(testClass)").path
        let failure = verifySnapshot(of: image,
                                     as: .image(precision: 0.995, perceptualPrecision: 0.98, scale: scale),
                                     named: name,
                                     snapshotDirectory: directory,
                                     file: file, testName: testName, line: line)
        if let failure { XCTFail(failure, file: file, line: line) }
    }
}

/// Writes parity inputs to `build/parity/` for `scripts/parity/native-parity.mjs`.
enum ParityOutput {
    nonisolated static var directory: URL {
        TVSnapshot.repoRoot.appendingPathComponent("build/parity", isDirectory: true)
    }

    static func write(png image: UIImage, as name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try XCTUnwrap(image.pngData(), "PNG encoding failed for \(name)")
        try data.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }

    static func write(json object: Any, as name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
