import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardTV

/// A6b: the status chip, drawn (precision 1.0).
///
/// Golden ↔ 07b:
/// - `status-chips-glass` → `tvOS / Status chip` `152:4203`, the ten kinds in
///   `Material=Liquid Glass`. That is the five A-series states (`152:4184`,
///   `152:4188`, `152:4192`, `152:4196`, `152:4200`) and DD22's five
///   (`275:138737`, `275:138741`, `275:138745`, `275:138749`, `275:138752`).
/// - `status-chips-regular-material` → the same kinds in
///   `Material=Regular material (pre-tvOS 26)` (`250:110500`…, `275:138755`…).
/// - `status-chips-opaque` → `Material=Opaque (Reduce Transparency)`
///   (`250:110504`…, `275:138773`…).
/// - `viewer-chip-standalone` → A7 `I166:204936;149:182603`, chip instance
///   `…;166:206937`: top-trailing inside title-safe, on its own surface (DD25).
/// - `viewer-overlay-chip` → A4 bar `154:8170` with the chip in the host
///   `…;154:8174` as plain content, not nested glass (DD25).
@MainActor
final class StatusChipSnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FigmaGeometryRegistry.shared.reset()
    }

    static let chips: [StatusChipContent] = [
        .init(kind: .override, badge: "Override", text: "2h 42m left · Holds until 9:00 PM", persistent: false),
        .init(kind: .silenced, badge: nil, text: "Silenced until 7:00 AM · showing a message", persistent: true),
        .init(kind: .paused, badge: nil, text: "Paused · showing the last update", persistent: false),
        .init(kind: .hubUnreachable, badge: nil, text: "Hub unreachable · showing the last update", persistent: true),
        .init(kind: .schedule, badge: nil, text: "Schedule · next change 9:00 PM", persistent: false),
        .init(kind: .override, badge: "Override", text: "Holds until canceled", persistent: false),
        .init(kind: .silenced, badge: nil, text: "Silenced until 7:00 AM · showing the last update", persistent: false),
        .init(kind: .silenced, badge: nil, text: "Silenced until 7:00 AM · showing the silence page", persistent: false),
        .init(kind: .reconnected, badge: nil, text: "Reconnected", persistent: false),
        .init(kind: .schedule, badge: nil, text: "Schedule", persistent: false),
    ]

    /// The A4b test board: a pigment row and text, so glass has something to show.
    static var board: some View {
        let cols = 29
        let pigments: [BoardColor] = [.red, .orange, .yellow, .green, .blue, .violet]
        let colour = (0..<cols).map { BoardCell.color(pigments[$0 % pigments.count]) }
        let blank = Array(repeating: BoardCell.blank, count: cols)
        func text(_ s: String) -> [BoardCell] {
            let chars = Array(s).map { $0 == " " ? BoardCell.blank : .character($0) }
            let pad = (cols - chars.count) / 2
            return Array(blank.prefix(pad)) + chars + Array(repeating: .blank, count: cols - pad - chars.count)
        }
        let cells = [blank, colour, text("GOOD EVENING MAYA"), colour, blank, text("64 CLEAR LO 55"),
                     colour, blank, text("N JUDAH 6 MIN"), text("MOVIE NIGHT 8 PM"), colour, blank]
        let layout = BoardLayout.make(rows: cells.count, cols: cols, cells: cells, tileHeight: 86)
        let fit = min(TVSnapshot.size.width / layout.width, TVSnapshot.size.height / layout.height)
        return BoardCanvas(layout: layout, background: .black)
            .frame(width: layout.width, height: layout.height)
            .scaleEffect(fit)
            .frame(width: TVSnapshot.size.width, height: TVSnapshot.size.height)
    }

    private func set(force: ViewerMaterial?, reduceTransparency: Bool = false) -> UIImage {
        TVSnapshot.image(ZStack(alignment: .topLeading) {
            Color.black
            Self.board
            ViewerGlassContainer {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(Self.chips.enumerated()), id: \.offset) { _, chip in
                        StatusChipView(content: chip, placement: .standalone)
                    }
                }
                .padding(.leading, PlatformTV.safeSide)
                .padding(.top, 40)
            }
        }
        .frame(width: TVSnapshot.size.width, height: TVSnapshot.size.height)
        .environment(\.viewerMaterialForce, force)
        .environment(\._accessibilityReduceTransparency, reduceTransparency), settle: 0.3, fullBleed: true)
    }

    private func assertEveryVariant(_ material: ViewerMaterial, file: StaticString = #filePath, line: UInt = #line) throws {
        let registry = FigmaGeometryRegistry.shared.snapshot()
        for chip in Self.chips {
            let node = StatusChipVariant(chip).node(material)
            let frame = try XCTUnwrap(registry[node]?.frame, "07b \(node) for \(chip.text)", file: file, line: line)
            // 07b: 16 + 38 + 16 = 70 (73 with the glass edge, 74 opaque): tvOS/Callout 31 and its padding.
            XCTAssertEqual(frame.height, 70, accuracy: 6, "\(chip.text) height", file: file, line: line)
        }
    }

    func testTheChipSetInLiquidGlass() throws {
        let image = set(force: nil)
        try assertEveryVariant(.liquidGlass)
        TVSnapshot.assertMatches(image, named: "status-chips-glass")
    }

    func testTheChipSetInTheRegularMaterial() throws {
        let image = set(force: .regularMaterial)
        try assertEveryVariant(.regularMaterial)
        TVSnapshot.assertMatches(image, named: "status-chips-regular-material")
    }

    func testTheChipSetOpaqueUnderReduceTransparency() throws {
        let image = set(force: nil, reduceTransparency: true)
        try assertEveryVariant(.opaque)
        TVSnapshot.assertMatches(image, named: "status-chips-opaque")
    }

    /// A7: on its own, top-trailing inside title-safe (x max 1840, y 60).
    func testTheStandaloneChipAtTheA7Position() throws {
        let image = TVSnapshot.image(ZStack {
            Color.black
            Self.board
            StandaloneStatusChip(content: Self.chips[0])
        }
        .frame(width: TVSnapshot.size.width, height: TVSnapshot.size.height), settle: 0.3, fullBleed: true)
        let registry = FigmaGeometryRegistry.shared.snapshot()
        let chip = try XCTUnwrap(registry[StandaloneStatusChip.probe]?.frame)
        XCTAssertEqual(chip.maxX, TVSnapshot.size.width - PlatformTV.safeSide, accuracy: 1, "trailing title-safe")
        XCTAssertEqual(chip.minY, PlatformTV.safeTopBottom, accuracy: 1, "top title-safe")
        XCTAssertEqual(registry[StandaloneStatusChip.a7Node]?.frame, chip)
        XCTAssertNotNil(registry[StatusChipVariant.override.node(.liquidGlass)], "its own glass surface (DD25)")
        TVSnapshot.assertMatches(image, named: "viewer-chip-standalone")
    }

    /// DD25: inside the bar the chip is plain content in the host slot, with
    /// no surface of its own.
    func testTheChipInTheOverlayBarIsPlainContent() throws {
        let image = TVSnapshot.image(ZStack {
            Color.black
            Self.board
            ViewerOverlay(panelName: "Living room TV", subtitle: "Split-flap · Maya’s FiestaPi",
                          chip: AnyView(StatusChipView(content: Self.chips[0], placement: .inBar)),
                          onInteraction: {}, onPanels: {}, onSettings: {})
        }
        .frame(width: TVSnapshot.size.width, height: TVSnapshot.size.height), settle: 0.3, fullBleed: true)
        let registry = FigmaGeometryRegistry.shared.snapshot()
        let host = try XCTUnwrap(registry[ViewerOverlay.chipHostNode]?.frame)
        let bar = try XCTUnwrap(registry[ViewerOverlay.barNode]?.frame)
        XCTAssertTrue(bar.contains(host))
        XCTAssertEqual(host.midY, bar.midY, accuracy: 1)
        for material in [ViewerMaterial.liquidGlass, .regularMaterial, .opaque] {
            XCTAssertNil(registry[StatusChipVariant.override.node(material)], "no nested chip surface in the bar")
        }
        TVSnapshot.assertMatches(image, named: "viewer-overlay-chip")
    }
}
