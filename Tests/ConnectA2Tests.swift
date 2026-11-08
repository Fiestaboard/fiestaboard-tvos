import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// A2 carry-forwards from the #16/#17 review, plus the Connect text probes.
@MainActor
final class ConnectA2Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        FigmaGeometryRegistry.shared.reset()
    }

    private func makeApp() -> AppModel {
        AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.a2.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
    }

    // MARK: 4.1 — secondary text is --muted-foreground, not the system colour

    /// The system `.secondary` label measured #919090 on CI where 07b binds
    /// --muted-foreground #a8a6a3; the hex guard cannot see a semantic
    /// colour, so this one does.
    func testNoScreenUsesTheSystemSecondaryColour() throws {
        let sources = TVSnapshot.repoRoot.appendingPathComponent("Sources")
        let pattern = try NSRegularExpression(pattern: #"\.foreground(Style|Color)\(\s*\.(secondary|tertiary)\b"#)
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated()
            where pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                offenders.append("\(url.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertEqual(offenders, [], "use Fiesta.Colors.mutedForeground")
    }

    // MARK: 4.2 — the address field sits on --secondary (surfaceRaised)

    /// Sentinel, as in A1: swap surfaceRaised and the field's fill follows.
    func testTheAddressFieldIsFilledWithSurfaceRaised() throws {
        let original = Fiesta.palette
        defer { Fiesta.palette = original }
        Fiesta.palette.surfaceRaised = TokenColor(hex: "#010203", red: 1 / 255, green: 2 / 255, blue: 3 / 255, alpha: 1)
        let app = makeApp()
        let image = TVSnapshot.image(ConnectScreen().environment(app)
            .frame(width: TVSnapshot.size.width, height: TVSnapshot.size.height)
            .background(Fiesta.Colors.background))
        let field = try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()["I166:147296;149:182603;166:147347"]?.frame,
                                  "the address field is probed as the A1 'Text field (system)' node")
        // Right of the placeholder text, vertically centred.
        let pixel = try XCTUnwrap(image.pixel(x: Int((field.maxX - 40) * 2), y: Int(field.midY * 2)))
        XCTAssertEqual(Int(pixel.r), 1, accuracy: 1)
        XCTAssertEqual(Int(pixel.g), 2, accuracy: 1)
        XCTAssertEqual(Int(pixel.b), 3, accuracy: 1)
    }

    // MARK: Text-equality probe inputs (§2.1 check 3)

    /// The Connect heading and the "still looking" row are tagged with their
    /// A1 node ids and carry their text, so native-parity.mjs can compare
    /// them with Figma's text nodes.
    func testConnectProbesCarryTheA1Text() async throws {
        let app = makeApp()
        let model = ConnectModel(app: app)
        let discovery = NeverEndingDiscovery()
        Task { await model.startScan(using: discovery, patience: .seconds(60)) }
        let hub = DiscoveredBoard(id: "http://192.168.1.20:4420", name: "FiestaBoard",
                                  host: URL(string: "http://192.168.1.20:4420")!)
        for _ in 0..<300 where model.boards.isEmpty {
            discovery.publish([hub])
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        _ = TVSnapshot.image(ConnectScreen(model: model).environment(app), settle: 0.3)
        model.stopScan()

        let slot = "I166:147296;149:182603"
        let nodes = try XCTUnwrap(ParityProbe.nodes(relativeTo: slot))
        func text(_ child: String) -> String? { nodes.first { $0.figma == "\(slot);\(child)" }?.label }
        XCTAssertEqual(text("166:147308"), TVCopy.Connect.eyebrow)
        XCTAssertEqual(text("166:147310"), TVCopy.Connect.title)
        XCTAssertEqual(text("166:147312"), TVCopy.Connect.subtitle)
        XCTAssertEqual(text("166:147342"), TVCopy.Connect.stillLooking, "found one, still scanning (A1)")
        XCTAssertEqual(text("166:147344"), TVCopy.Connect.manualLabel)
        XCTAssertEqual(text("166:147327"), "FiestaBoard", "DD8: the card title is the advertised name")
    }
}
