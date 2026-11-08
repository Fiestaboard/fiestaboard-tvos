import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// A1 — the token bridge (PHASE-4-TV-PLAN §2.2 A1, §2.1 check 1).
///
/// The app's colours, board pigments and TV platform values come from two
/// vendored inputs through `scripts/tokens/generate-swift.mjs`:
/// - `Tokens/fiestaui-tokens.json`: `@fiestaboard/ui` `tokens.json`, built
///   from FiestaUI alpha by its own extractor;
/// - `Tokens/platform-tv.json`: Figma's "Platform · TV" variables.
/// These tests read both inputs from the source tree and hold the generated
/// Swift, the app palette and the board renderer to them.
@MainActor
final class TokenBridgeTests: XCTestCase {

    private func json(_ path: String) throws -> [String: Any] {
        let url = TVSnapshot.repoRoot.appendingPathComponent(path)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], path)
    }

    /// name → (hex, alpha) for one colour group of tokens.json.
    private func colours(_ group: [String: Any]) -> [String: (hex: String, alpha: Double)] {
        var out: [String: (String, Double)] = [:]
        for (name, raw) in group {
            guard let token = raw as? [String: Any], let value = token["$value"] as? [String: Any],
                  let hex = value["hex"] as? String else { continue }
            out[name] = (hex.lowercased(), (value["alpha"] as? Double) ?? 1)
        }
        return out
    }

    // MARK: Generated values = the inputs

    func testGeneratedColoursEqualTokensJSON() throws {
        let color = try XCTUnwrap(try json("Tokens/fiestaui-tokens.json")["color"] as? [String: Any])
        for (mode, generated) in [("dark", FiestaTokenValues.Dark.all), ("light", FiestaTokenValues.Light.all)] {
            let expected = colours(try XCTUnwrap(color[mode] as? [String: Any]))
            XCTAssertEqual(Set(generated.keys), Set(expected.keys), mode)
            for (name, want) in expected {
                let got = try XCTUnwrap(generated[name], "\(mode).\(name)")
                XCTAssertEqual(got.hex, want.hex, "\(mode).\(name)")
                XCTAssertEqual(got.alpha, want.alpha, accuracy: 0.0001, "\(mode).\(name)")
            }
        }
    }

    /// Board pigments: tokens.json `board.*`, the generated table, the
    /// renderer's `BoardColor`, and the variables Figma binds on the TV
    /// board component `149:182628` must all agree.
    func testBoardColoursAgreeAcrossTokensRendererAndFigma() throws {
        let board = colours(try XCTUnwrap(try json("Tokens/fiestaui-tokens.json")["board"] as? [String: Any]))
        let figma = try XCTUnwrap(try json("Tests/Fixtures/figma-content/tv-board-living-room-29x12.json")["boundVariables"]
                                  as? [String: String])
        XCTAssertEqual(Set(FiestaTokenValues.Board.all.keys), Set(board.keys))
        for colour in BoardColor.allCases {
            let token = try XCTUnwrap(board[colour.rawValue], colour.rawValue)
            XCTAssertEqual(colour.hex.lowercased(), token.hex, "BoardColor.\(colour)")
            XCTAssertEqual(FiestaTokenValues.Board.all[colour.rawValue]?.hex, token.hex)
            if let bound = figma[colour.rawValue] {
                XCTAssertEqual(bound.lowercased(), token.hex, "Figma 149:182628 binds \(colour)")
            }
        }
        XCTAssertEqual(figma["text-on-dark"]?.lowercased(), FiestaTokenValues.Board.textOnDark.hex)
    }

    func testPlatformTVEqualsPlatformTVJSON() throws {
        let tv = try XCTUnwrap(try json("Tokens/platform-tv.json")["tv"] as? [String: Any])
        func value(_ group: String, _ name: String) throws -> Double {
            let g = try XCTUnwrap(tv[group] as? [String: Any])
            let t = try XCTUnwrap(g[name] as? [String: Any])
            return try XCTUnwrap((t["$value"] as? [String: Any])?["value"] as? Double)
        }
        XCTAssertEqual(PlatformTV.safeSide, CGFloat(try value("tvos", "safe-side")))
        XCTAssertEqual(PlatformTV.safeTopBottom, CGFloat(try value("tvos", "safe-top-bottom")))
        XCTAssertEqual(PlatformTV.cardRadius, CGFloat(try value("tvos", "card-radius")))
        XCTAssertEqual(PlatformTV.focusOutline, CGFloat(try value("focus", "outline")))
        // The spec values Figma's A1 safe-area frame draws (80 / 60).
        XCTAssertEqual(PlatformTV.safeSide, 80)
        XCTAssertEqual(PlatformTV.safeTopBottom, 60)
    }

    // MARK: The app palette reads the tokens

    /// Each app role maps to the FiestaUI dark token the 07b frames bind
    /// (A1 binds --background, --foreground, --muted-foreground, --primary,
    /// --secondary; the tvOS panel card binds --card).
    func testTheAppPaletteIsTheDarkTokens() {
        let dark = FiestaTokenValues.Dark.self
        let palette = Fiesta.Palette.tokens
        XCTAssertEqual(palette.background, dark.background)
        XCTAssertEqual(palette.surface, dark.card)
        XCTAssertEqual(palette.surfaceRaised, dark.secondary)
        XCTAssertEqual(palette.foreground, dark.foreground)
        XCTAssertEqual(palette.mutedForeground, dark.mutedForeground)
        XCTAssertEqual(palette.brand, dark.primary)
        XCTAssertEqual(palette.border, dark.border)
        XCTAssertEqual(palette.destructive, dark.destructive)
        XCTAssertEqual(palette.offline, dark.primary)
        XCTAssertEqual(Fiesta.Colors.brandHex, dark.primary.hex)
    }

    // MARK: Sentinel (§2.1 check 1)

    /// Swap a token for a sentinel no design would use, re-render, and the
    /// sampled pixel must follow. A hard-coded colour that merely equals
    /// the token would not.
    private static let sentinel = TokenColor(hex: "#010203", red: 1 / 255, green: 2 / 255, blue: 3 / 255, alpha: 1)

    private func assertSentinel(_ pixel: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)?, _ what: String,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let p = try XCTUnwrap(pixel, file: file, line: line)
        XCTAssertEqual(Int(p.r), 1, accuracy: 1, what, file: file, line: line)
        XCTAssertEqual(Int(p.g), 2, accuracy: 1, what, file: file, line: line)
        XCTAssertEqual(Int(p.b), 3, accuracy: 1, what, file: file, line: line)
    }

    func testSentinelBackgroundFollowsTheToken() throws {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.sentinel.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
        app.route = .connect
        let original = Fiesta.palette
        defer { Fiesta.palette = original }

        let before = TVSnapshot.image(RootView().environment(app))
        let corner = try XCTUnwrap(before.pixel(x: 8, y: 8))
        XCTAssertFalse(corner.r == 1 && corner.g == 2 && corner.b == 3, "precondition: not already the sentinel")

        Fiesta.palette.background = Self.sentinel
        let after = TVSnapshot.image(RootView().environment(app))
        try assertSentinel(after.pixel(x: 8, y: 8), "RootView's ground must read Fiesta.palette.background")
    }

    func testSentinelSurfaceFollowsTheToken() throws {
        let original = Fiesta.palette
        defer { Fiesta.palette = original }
        Fiesta.palette.surface = Self.sentinel
        let card = DiscoveredBoardCard(board: DiscoveredBoard(id: "x", name: "Maya’s FiestaPi",
                                                               host: URL(string: "http://192.168.1.20")!),
                                       address: "192.168.1.20", isConnecting: false) {}
        let image = TVSnapshot.image(ZStack(alignment: .topLeading) {
            Color.black
            card.frame(width: 520).figmaNode("card")
        })
        let frame = try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()["card"]?.frame)
        // Inside the card, right of its text and above its bottom edge.
        try assertSentinel(image.pixel(x: Int((frame.maxX - 30) * 2), y: Int((frame.maxY - 20) * 2)),
                           "DiscoveredBoardCard's platter must read Fiesta.palette.surface")
    }

    // MARK: Structural board probe (§2.1 check 5): 149:182628, zero tolerance

    func testTheRendererModelMatchesFigmaTheLivingRoomBoard() throws {
        let fixture = try json("Tests/Fixtures/figma-content/tv-board-living-room-29x12.json")
        let rows = try XCTUnwrap(fixture["rows"] as? Int), cols = try XCTUnwrap(fixture["cols"] as? Int)
        let raw = try XCTUnwrap(fixture["cells"] as? [[String]])
        let cells: [[BoardCell]] = try raw.map { row in
            try row.map { cell in
                if cell.isEmpty { return .blank }
                if cell.hasPrefix("color:") {
                    return .color(try XCTUnwrap(BoardColor(rawValue: String(cell.dropFirst(6))), cell))
                }
                return .character(try XCTUnwrap(cell.first))
            }
        }
        XCTAssertEqual(rows, 12)
        XCTAssertEqual(cols, 29)
        let tile = try XCTUnwrap(fixture["tile"] as? [String: Any])
        let tileHeight = try XCTUnwrap(tile["height"] as? Double)
        let layout = BoardLayout.make(rows: rows, cols: cols, cells: cells, tileHeight: tileHeight)

        XCTAssertEqual(layout.tiles.count, rows * cols, "every Figma tile is drawn")
        for t in layout.tiles {
            XCTAssertEqual(t.cell, cells[t.row][t.col], "tile r\(t.row) c\(t.col)")
        }
        let colourTiles = layout.tiles.filter { if case .color = $0.cell { return true } else { return false } }
        XCTAssertEqual(colourTiles.count, 58)
        // Colour codes 63–68 round-trip to the same pigments Figma shows.
        for t in colourTiles {
            guard case .color(let c) = t.cell else { continue }
            let code = 63 + try XCTUnwrap(BoardColor.allCases.firstIndex(of: c))
            XCTAssertEqual(BoardColor(code: code), c)
        }
        // Size class lg (32×46) at Figma's tile height.
        let first = try XCTUnwrap(layout.tiles.first)
        XCTAssertEqual(first.width, try XCTUnwrap(tile["width"] as? Double), accuracy: 1)
        XCTAssertEqual(first.height, tileHeight, accuracy: 0)

        // Informational, for the parity report: pitch vs Figma (39 / 53).
        let second = try XCTUnwrap(layout.tiles.first { $0.row == 0 && $0.col == 1 })
        let below = try XCTUnwrap(layout.tiles.first { $0.row == 1 && $0.col == 0 })
        try ParityOutput.write(json: [
            "figmaNode": "149:182628", "tiles": layout.tiles.count, "colourTiles": colourTiles.count,
            "tile": ["width": first.width, "height": first.height],
            "pitch": ["x": second.x - first.x, "y": below.y - first.y],
            "figmaPitch": ["x": tile["pitchX"] as Any, "y": tile["pitchY"] as Any],
            "board": ["width": layout.width, "height": layout.height],
        ], as: "board-149-182628.structure.json")
    }

    // MARK: Guard

    /// No colour literal outside the bridge: a hex typed into a view would
    /// pass a value check while ignoring the token. The white-hardware
    /// unlit flap (#e8e8e8) has no FiestaUI token and is allow-listed.
    func testNoHexColourLiteralsOutsideTheBridge() throws {
        let sources = TVSnapshot.repoRoot.appendingPathComponent("Sources")
        let allowedFiles: Set<String> = ["FiestaTokens+Generated.swift"]
        let allowedLiterals: Set<String> = ["#e8e8e8"]
        let pattern = try NSRegularExpression(pattern: "\"#[0-9A-Fa-f]{6}\"")
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" {
            guard !allowedFiles.contains(url.lastPathComponent) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let literal = String(text[Range(match.range, in: text)!]).trimmingCharacters(in: ["\""]).lowercased()
                if !allowedLiterals.contains(literal) { offenders.append("\(url.lastPathComponent): \(literal)") }
            }
        }
        XCTAssertEqual(offenders, [], "use FiestaTokenValues / Fiesta.palette instead")
    }
}
