import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardTV

/// A0 — the D7 parity foundation (PHASE-4-TV-PLAN §2.1, §2.2).
///
/// Proves, in the unit-test host:
/// - the simulator is an Apple TV 4K at scale 2, so a shot is the 3840×2160
///   grid of a Figma `scale=2` export;
/// - swift-snapshot-testing compares 1920×1080 pt SwiftUI shots, including
///   the board's single `Canvas`;
/// - the DEBUG `figmaNode` modifier feeds `FigmaGeometryRegistry` through
///   `onGeometryChange`, in global points;
/// - the Connect screen produces parity inputs for the A1 ref.
///
/// What `drawHierarchy` makes of glass is measured, not asserted: it matched
/// `XCUIScreen` on tvOS 26.2 and 27.2, but the API does not promise it, so
/// the gating glass proof is the XCUITest in `ParityShotsUITests`.
@MainActor
final class ParitySnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FigmaGeometryRegistry.shared.reset()
    }

    // MARK: Pixel grid

    func testTheSimulatorIsAnAppleTV4KAtScaleTwo() {
        XCTAssertEqual(UIScreen.main.scale, 2,
                       "parity shots need the Apple TV 4K simulator; select-tvos-simulator.sh prefers it")
        XCTAssertEqual(UIScreen.main.bounds.size, TVSnapshot.size)
        XCTAssertEqual(UIScreen.main.nativeBounds.size, CGSize(width: 3840, height: 2160))
    }

    func testAShotIsTheFullScreenAtScaleTwo() throws {
        let image = TVSnapshot.image(Color.red)
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cg.width, 3840)
        XCTAssertEqual(cg.height, 2160)
    }

    /// Goldens are 8-bit sRGB. The renderer's default on the P3 4K simulator
    /// is the extended range — 16 bits per channel — which nothing reads and
    /// which doubles every golden (review #15, 6.1).
    func testAShotIsEightBitStandardRange() throws {
        let cg = try XCTUnwrap(TVSnapshot.image(Color.red).cgImage)
        XCTAssertEqual(cg.bitsPerComponent, 8)
        XCTAssertEqual(cg.bitsPerPixel, 32)
    }

    /// The parity artifact names the exact simulator runtime (review #15,
    /// 6.4): goldens are split only by OS major, so a runner image moving
    /// 26.2 → 26.x must be visible in the evidence.
    func testParityOutputRecordsTheSimulatorRuntime() throws {
        try ParityOutput.writeRuntime()
        let data = try Data(contentsOf: ParityOutput.directory.appendingPathComponent("runtime.json"))
        let runtime = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let os = try XCTUnwrap(runtime["osVersion"] as? String)
        XCTAssertTrue(os.hasPrefix("\(TVSnapshot.osMajor)."), os)
        XCTAssertEqual(runtime["goldenDirectory"] as? String, "tvOS\(TVSnapshot.osMajor)")
        XCTAssertNotNil(runtime["runtimeBuild"] as? String, "SIMULATOR_RUNTIME_BUILD_VERSION")
        XCTAssertNotNil(runtime["deviceModel"] as? String)
        XCTAssertEqual(runtime["scale"] as? Double, 2)
    }

    // MARK: Geometry registry (M8)

    func testFigmaNodeRecordsItsGlobalFrameAndLabel() throws {
        let view = ZStack(alignment: .topLeading) {
            Color.black
            Text("Hello")
                .frame(width: 300, height: 80)
                .figmaNode("1:2", label: "Hello")
                .offset(x: 100, y: 50)
        }
        .figmaNode("1:1")
        _ = TVSnapshot.image(view, fullBleed: true)

        let entries = FigmaGeometryRegistry.shared.snapshot()
        let root = try XCTUnwrap(entries["1:1"], "the root must register")
        XCTAssertEqual(root.frame, CGRect(origin: .zero, size: TVSnapshot.size))
        let text = try XCTUnwrap(entries["1:2"])
        XCTAssertEqual(text.label, "Hello")
        XCTAssertEqual(text.frame.minX, 100, accuracy: 1)
        XCTAssertEqual(text.frame.minY, 50, accuracy: 1)
        XCTAssertEqual(text.frame.width, 300, accuracy: 1)
        XCTAssertEqual(text.frame.height, 80, accuracy: 1)
    }

    func testProbesAreRelativeToTheSlotRoot() throws {
        let registry = FigmaGeometryRegistry()
        registry.record("slot", label: nil, frame: CGRect(x: 10, y: 20, width: 1920, height: 1080))
        registry.record("child", label: "Connect", frame: CGRect(x: 110, y: 220, width: 50, height: 40))
        let nodes = try XCTUnwrap(ParityProbe.nodes(relativeTo: "slot", in: registry))
        XCTAssertEqual(nodes.first { $0.figma == "child" }?.rect, CGRect(x: 100, y: 200, width: 50, height: 40))
        XCTAssertNil(ParityProbe.nodes(relativeTo: "missing", in: registry))
    }

    func testTheRegistryExportsJSONTheUITestsCanRead() throws {
        let registry = FigmaGeometryRegistry()
        registry.record("b", label: nil, frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        registry.record("a", label: "A", frame: CGRect(x: 5, y: 6, width: 7, height: 8))
        let decoded = try JSONDecoder().decode(FigmaGeometryRegistry.Export.self, from: registry.exportData())
        XCTAssertEqual(decoded.nodes.map(\.id), ["a", "b"])
        XCTAssertEqual(decoded.nodes.first?.frame, CGRect(x: 5, y: 6, width: 7, height: 8))
        XCTAssertEqual(decoded.nodes.first?.label, "A")
    }

    // MARK: Snapshots

    /// The custom board: a single `Canvas`, drawn at the display scale.
    func testBoardCanvasSnapshotAtFourK() throws {
        let row: [BoardCell] = [.color(.red), .character("F"), .character("I"), .character("E"),
                                .character("S"), .character("T"), .character("A"), .color(.green)]
        let blank = Array(repeating: BoardCell.blank, count: row.count)
        let layout = BoardLayout.make(rows: 3, cols: row.count, cells: [blank, row, blank], tileHeight: 160)
        let view = ZStack {
            Color.black
            BoardCanvas(layout: layout, background: .black)
                .frame(width: layout.width, height: layout.height)
        }
        let image = TVSnapshot.image(view, fullBleed: true)

        // The red tile's centre, in pixels: the board is centred, row 1, col 0.
        let originX = (TVSnapshot.size.width - layout.width) / 2
        let originY = (TVSnapshot.size.height - layout.height) / 2
        let tile = layout.tiles[row.count] // row 1, col 0
        XCTAssertEqual(tile.cell, .color(.red))
        let px = Int((originX + tile.x + tile.width / 2) * TVSnapshot.scale)
        // Below the split, clear of the seam.
        let py = Int((originY + tile.y + tile.height * 0.75) * TVSnapshot.scale)
        let red = try XCTUnwrap(image.pixel(x: px, y: py))
        XCTAssertGreaterThan(Int(red.r), 150, "the Canvas must paint into the scale-2 shot")
        XCTAssertLessThan(Int(red.g), 110)

        TVSnapshot.assertMatches(image, named: "board-fiesta")
    }

    /// A1 baseline: today's Connect screen with one board found, as parity
    /// inputs for `native-parity.mjs` and as a regression golden.
    func testConnectScreenSnapshotAndA1ParityInputs() async throws {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.parity.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
        let model = ConnectModel(app: app)
        let discovery = NeverEndingDiscovery()
        // Never-ending, so the screen's own `.onAppear` scan is turned away
        // and the board stays. Re-publish until the scan has subscribed.
        Task { await model.startScan(using: discovery, patience: .seconds(60)) }
        let board = DiscoveredBoard(id: "http://192.168.1.20:4420", name: "FiestaBoard",
                                    host: URL(string: "http://192.168.1.20:4420")!)
        for _ in 0..<300 where model.boards.isEmpty {
            discovery.publish([board])
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(model.boards.count, 1)

        // A4a: as the device draws it, inside the 80/60 safe area.
        let image = TVSnapshot.image(ConnectScreen(model: model)
            .environment(app)
            .background(Fiesta.Colors.background), settle: 0.3)
        model.stopScan()

        let slot = "I166:147296;149:182603"
        let nodes = try XCTUnwrap(ParityProbe.nodes(relativeTo: slot), "ConnectScreen must tag the A1 slot")
        XCTAssertEqual(nodes.first { $0.figma == slot }?.rect.size, TVSnapshot.size)
        XCTAssertTrue(nodes.contains { $0.figma.hasSuffix("166:147351") }, "the Connect button is probed")

        try ParityOutput.writeRuntime()
        try ParityOutput.write(png: image, as: "a1-connect")
        try ParityOutput.write(json: ParityProbe.json(ref: "a1-connect", root: slot, scale: TVSnapshot.scale),
                               as: "a1-connect.probes.json")
        TVSnapshot.assertMatches(image, named: "connect-one-board")
    }

    /// Informational: what `drawHierarchy` makes of `.glassEffect`. The
    /// numbers go to `build/parity/glass-drawhierarchy.json` and the A0
    /// status; `ParityShotsUITests` holds the assertion.
    func testGlassUnderDrawHierarchyIsMeasuredNotAsserted() throws {
        let image = TVSnapshot.image(ParityFixtureView(kind: .glass), settle: 0.3, fullBleed: true)
        let panel = try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()[ParityFixtureView.glassNode]?.frame)
        let measurement = try XCTUnwrap(GlassProbe.measure(try XCTUnwrap(image.cgImage),
                                                           scale: TVSnapshot.scale, panel: panel))
        let attachment = XCTAttachment(image: image)
        attachment.name = "Glass fixture via drawHierarchy"
        attachment.lifetime = .keepAlways
        add(attachment)
        try ParityOutput.write(png: image, as: "glass-drawhierarchy")
        try ParityOutput.write(json: measurement.dictionary, as: "glass-drawhierarchy.json")
        XCTAssertGreaterThan(measurement.samples, 10)
    }
}
