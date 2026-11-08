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
/// Glass is not guaranteed by the API here: `drawHierarchy` is documented as
/// a view-hierarchy render, not a window-server capture. Measured, not
/// asserted: on tvOS 26.2 and 27.2 it rendered `.glassEffect` exactly as
/// `XCUIScreen` did (see `testGlassUnderDrawHierarchyIsMeasuredNotAsserted`).
/// The focus platter is never captured here — an offscreen window takes no
/// focus — so glass and focus states are gated by XCUITest
/// (`ParityShotsUITests`) through `XCUIScreen`.
///
/// Shots are 8-bit standard range: the P3 4K simulator otherwise renders
/// 16 bits per channel, which nothing reads and which doubles each golden.
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
    ///
    /// The window's safe area is the device's 80/60 title-safe (A4a), and
    /// screens are laid out inside it, as on the TV. `fullBleed` ignores it,
    /// for what the device also draws edge to edge (the board, fixtures).
    static func image<V: View>(_ view: V, settle: TimeInterval = 0.1, fullBleed: Bool = false) -> UIImage {
        let host = UIHostingController(rootView: view
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
            .ignoresSafeArea(fullBleed ? .all : []))
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
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }

    /// Golden tolerance (A3). Every pixel must match within the perceptual
    /// threshold: `precision` 1.0 leaves no pixel budget, so a five-glyph
    /// copy change fails (at 0.995, DD12's dropped ":4420" passed), while
    /// `perceptualPrecision` 0.98 still absorbs glyph anti-aliasing.
    /// `SnapshotToleranceTests` proves both halves.
    static let precision: Float = 1.0
    static let perceptualPrecision: Float = 0.98

    /// The library's image comparison at the golden tolerance (or another
    /// `precision`): nil when the two match.
    static func difference(_ a: UIImage, _ b: UIImage, precision: Float = precision) -> String? {
        Snapshotting<UIImage, UIImage>.image(precision: precision, perceptualPrecision: perceptualPrecision, scale: scale)
            .diffing.diff(a, b)?.0
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
                                     as: .image(precision: precision, perceptualPrecision: perceptualPrecision, scale: scale),
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

    /// `runtime.json`: the exact simulator runtime and device behind the
    /// shots. Goldens are split only by OS major, so a runner image moving
    /// to another minor shows up here.
    static func writeRuntime() throws {
        let env = ProcessInfo.processInfo.environment
        let version = ProcessInfo.processInfo.operatingSystemVersion
        try write(json: [
            "osVersion": env["SIMULATOR_RUNTIME_VERSION"]
                ?? "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "runtimeBuild": env["SIMULATOR_RUNTIME_BUILD_VERSION"] ?? "unknown",
            "deviceModel": env["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.model,
            "goldenDirectory": "tvOS\(TVSnapshot.osMajor)",
            "scale": Double(UIScreen.main.scale),
        ], as: "runtime.json")
    }

    static func write(json object: Any, as name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
