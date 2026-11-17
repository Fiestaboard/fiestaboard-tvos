import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardTV

/// A4b — the viewer overlay bar, drawn (PHASE-4-TV-PLAN §2.2 A4b; the A4a
/// carry-forward "a snapshot that shows the overlay bar at (80, 60, 1760)").
///
/// Golden ↔ 07b:
/// - `viewer-overlay-glass` → A4 `166:191865` (bar `I166:191865;149:182603;166:193875`),
///   variant `Material=Liquid Glass (tvOS 26)` `154:8170`.
/// - `viewer-overlay-regular-material` → `Material=Regular material (pre-tvOS 26)`
///   `250:110532` (DD4 interim, forced: no runner can run the pre-26 branch).
/// - `viewer-overlay-opaque` → `Material=Opaque (Reduce Transparency)` `250:110540`.
///
/// Each shot is full-bleed over a fixed split-flap board, as the viewer is
/// (DD24): glass needs something behind it to be seen. Unfocused: an
/// offscreen window takes no focus, so the focus platter is XCUITest's
/// (`ViewerNavigationUITests`).
@MainActor
final class ViewerOverlaySnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FigmaGeometryRegistry.shared.reset()
    }

    /// A busy board under the bar: a pigment row right where the bar sits,
    /// then text, so translucency (or its absence) is visible.
    private var board: some View {
        let cols = 29
        let pigments: [BoardColor] = [.red, .orange, .yellow, .green, .blue, .violet]
        let colour = (0..<cols).map { BoardCell.color(pigments[$0 % pigments.count]) }
        let blank = Array(repeating: BoardCell.blank, count: cols)
        func text(_ s: String) -> [BoardCell] {
            let chars = Array(s).map { $0 == " " ? BoardCell.blank : .character($0) }
            let pad = (cols - chars.count) / 2
            return Array(blank.prefix(pad)) + chars + Array(repeating: .blank, count: cols - pad - chars.count)
        }
        let cells = [blank, colour, text("GOOD EVENING MAYA"), blank, blank, text("64 CLEAR LO 55"),
                     blank, blank, text("N JUDAH 6 MIN"), text("MOVIE NIGHT 8 PM"), colour, blank]
        let layout = BoardLayout.make(rows: cells.count, cols: cols, cells: cells, tileHeight: 86)
        // Full-bleed at 1920 wide (DD24), as the viewer fits it.
        let fit = min(TVSnapshot.size.width / layout.width, TVSnapshot.size.height / layout.height)
        return BoardCanvas(layout: layout, background: .black)
            .frame(width: layout.width, height: layout.height)
            .scaleEffect(fit)
            .frame(width: TVSnapshot.size.width, height: TVSnapshot.size.height)
    }

    private func overlay(chip: AnyView? = nil) -> some View {
        ViewerOverlay(panelName: "Living room TV", subtitle: "Split-flap · Maya’s FiestaPi", chip: chip,
                      onInteraction: {}, onPanels: {}, onSettings: {})
    }

    private func shot(force: ViewerMaterial? = nil, reduceTransparency: Bool = false,
                      chip: AnyView? = nil) -> UIImage {
        TVSnapshot.image(ZStack {
            Color.black
            board
            overlay(chip: chip)
        }
        .frame(width: TVSnapshot.size.width, height: TVSnapshot.size.height)
        .environment(\.viewerMaterialForce, force)
        .environment(\._accessibilityReduceTransparency, reduceTransparency), settle: 0.3, fullBleed: true)
    }

    private func bar(file: StaticString = #filePath, line: UInt = #line) throws -> CGRect {
        try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()[ViewerOverlay.barNode]?.frame,
                      "the bar must register A4's overlay instance", file: file, line: line)
    }

    private func assertBarAtTheA4Frame(file: StaticString = #filePath, line: UInt = #line) throws {
        let bar = try bar(file: file, line: line)
        XCTAssertEqual(bar.minX, PlatformTV.safeSide, accuracy: 1, "x", file: file, line: line)
        XCTAssertEqual(bar.minY, PlatformTV.safeTopBottom, accuracy: 1, "y", file: file, line: line)
        XCTAssertEqual(bar.width, 1760, accuracy: 1, "width", file: file, line: line)
    }

    private func assertVariant(_ node: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let registry = FigmaGeometryRegistry.shared.snapshot()
        let variant = try XCTUnwrap(registry[node]?.frame, "the bar is drawn as 07b \(node)", file: file, line: line)
        let bar = try bar(file: file, line: line)
        XCTAssertEqual(variant, bar, "the material is the bar's own surface", file: file, line: line)
        for other in ["154:8170", "250:110532", "250:110540"] where other != node {
            XCTAssertNil(registry[other], "only one material at a time (\(other))", file: file, line: line)
        }
    }

    /// The A4a carry-forward: the bar, visible, at (80, 60), 1760 wide.
    func testTheGlassOverlayBarAtTheA4Frame() throws {
        let image = shot()
        try assertBarAtTheA4Frame()
        try assertVariant(ViewerMaterial.liquidGlass.overlayVariantNode)
        // 07b `154:8170`: 40 pt in from the bar to the title.
        let title = try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()[ViewerOverlay.titleNode]?.frame)
        XCTAssertEqual(title.minX - PlatformTV.safeSide, 40, accuracy: 1, "title inset")
        XCTAssertNil(FigmaGeometryRegistry.shared.snapshot()[ViewerOverlay.chipHostNode],
                     "no chip until A6b: the host takes no space")
        TVSnapshot.assertMatches(image, named: "viewer-overlay-glass")
    }

    /// DD4 interim (a): below tvOS 26, forced here.
    func testTheRegularMaterialFallback() throws {
        let image = shot(force: .regularMaterial)
        try assertBarAtTheA4Frame()
        try assertVariant(ViewerMaterial.regularMaterial.overlayVariantNode)
        TVSnapshot.assertMatches(image, named: "viewer-overlay-regular-material")
    }

    /// DD4 interim (b): Reduce Transparency, an explicitly opaque bar.
    func testReduceTransparencyDrawsTheOpaqueBar() throws {
        let image = shot(reduceTransparency: true)
        try assertBarAtTheA4Frame()
        try assertVariant(ViewerMaterial.opaque.overlayVariantNode)
        // Opaque means the board cannot read through: the centre of the
        // bar's empty middle is the --card token exactly.
        let bar = try bar()
        let sample = try XCTUnwrap(image.pixel(x: Int(bar.midX * TVSnapshot.scale), y: Int(bar.midY * TVSnapshot.scale)))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Fiesta.Colors.surface).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(Int(sample.r), Int((r * 255).rounded()), accuracy: 2)
        XCTAssertEqual(Int(sample.g), Int((g * 255).rounded()), accuracy: 2)
        XCTAssertEqual(Int(sample.b), Int((b * 255).rounded()), accuracy: 2)
        TVSnapshot.assertMatches(image, named: "viewer-overlay-opaque")
    }

    /// The chip host (07b `…;154:8174`): A6b's status chip sits after the
    /// title, 28 pt on, centred in the bar, and reads the bar's material.
    func testTheChipHostPlacesAChipAfterTheTitle() throws {
        var seen: ViewerMaterial?
        let chip = AnyView(ChipProbe { seen = $0 })
        _ = shot(force: .opaque, chip: chip)
        let registry = FigmaGeometryRegistry.shared.snapshot()
        let title = try XCTUnwrap(registry[ViewerOverlay.titleNode]?.frame)
        let host = try XCTUnwrap(registry[ViewerOverlay.chipHostNode]?.frame, "the host registers when it holds a chip")
        let bar = try bar()
        XCTAssertEqual(host.minX - title.maxX, 28, accuracy: 1, "07b gap 28")
        XCTAssertEqual(host.midY, bar.midY, accuracy: 1, "centred in the bar")
        XCTAssertTrue(bar.contains(host))
        XCTAssertEqual(seen, .opaque, "the chip reads the bar's material from the environment")
        try assertBarAtTheA4Frame()
    }
}

private struct ChipProbe: View {
    let report: (ViewerMaterial) -> Void
    @Environment(\.viewerMaterial) private var material
    var body: some View {
        Text("Override")
            .font(Fiesta.Text.caption)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .viewerSurface(material, in: Capsule())
            .onAppear { report(material) }
    }
}
