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
    /// tvOS draws a translucent platter over any TextField, so the sampled
    /// colour is the token *seen through* system chrome: a magenta sentinel
    /// must come out magenta, and the real token must be lighter than the
    /// ground it sits on.
    func testTheAddressFieldIsFilledWithSurfaceRaised() throws {
        func fieldPixel() throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            FigmaGeometryRegistry.shared.reset()
            let image = TVSnapshot.image(ConnectScreen().environment(makeApp())
                .frame(width: TVSnapshot.size.width, height: TVSnapshot.size.height)
                .background(Fiesta.Colors.background))
            let field = try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()["I166:147296;149:182603;166:147347"]?.frame,
                                      "the address field is probed as the A1 'Text field (system)' node")
            // Right of the placeholder text, vertically centred.
            return try XCTUnwrap(image.pixel(x: Int((field.maxX - 40) * 2), y: Int(field.midY * 2)))
        }
        let original = Fiesta.palette
        defer { Fiesta.palette = original }

        let token = try fieldPixel()
        let ground = FiestaTokenValues.Dark.background
        XCTAssertGreaterThan(Int(token.r), Int(ground.red * 255) + 8, "the field sits on surfaceRaised, not the ground")

        Fiesta.palette.surfaceRaised = TokenColor(hex: "#ff00ff", red: 1, green: 0, blue: 1, alpha: 1)
        let sentinel = try fieldPixel()
        XCTAssertGreaterThan(Int(sentinel.r), 120, "the fill must follow Fiesta.palette.surfaceRaised")
        XCTAssertGreaterThan(Int(sentinel.b), 120)
        XCTAssertLessThan(Int(sentinel.g), 60)
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
