import XCTest
@testable import FiestaBoardTV

final class PixelLayerTests: XCTestCase {
    static func frame(_ layers: [Any]? = nil, characters: [[Int]]? = nil) throws -> PanelFrame {
        var json: [String: Any] = ["rows": 1, "cols": 1]
        if let layers { json["layers"] = layers }
        if let characters { json["characters"] = characters }
        return try JSONDecoder().decode(PanelFrame.self, from: JSONSerialization.data(withJSONObject: json))
    }

    static func layer(_ bytes: [UInt8], x: Int = 0, y: Int = 0, width: Int = 1, height: Int = 1) -> [String: Any] {
        ["x": x, "y": y, "width": width, "height": height, "rgba": Data(bytes).base64EncodedString()]
    }

    static func panel(width: Int = 5, height: Int = 7, mono: String? = nil) throws -> Panel {
        var json = try JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as! [String: Any]
        var spec: [String: Any] = ["geometry": ["kind": "pixels", "width": width, "height": height], "font": "5x7"]
        if let mono { spec["color"] = ["kind": "monochrome", "color": mono] }
        json["render_style"] = "led_matrix"
        json["device_model_spec"] = spec
        return try JSONDecoder().decode(Panel.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testPixelOnlyChangesAndRemovalChangeFrameEquality() throws {
        let red = try Self.frame([Self.layer([255, 0, 0, 255])])
        let blue = try Self.frame([Self.layer([0, 0, 255, 255])])
        XCTAssertNotEqual(red, blue, "pixel-only updates must invalidate consumers")
        XCTAssertNotEqual(red, try Self.frame(), "removing all layers must clear previous pixels")
    }

    func testLayersOverwriteTextInOrderWithoutBlending() throws {
        let frame = try Self.frame([
            Self.layer([20, 40, 60, 1, 255, 0, 0, 0, 0, 0, 0, 255], width: 3),
            Self.layer([0, 0, 255, 128], x: 0),
        ], characters: [[63]])
        let raster = MatrixRaster.make(panel: try Self.panel(),
            cells: BoardTables.cells(from: frame.characters!, code62: .degree), layers: frame.layers)
        XCTAssertEqual(Array(raster.pixels.prefix(5)), [0x0000ff, 0xeb4034, 0, 0xeb4034, 0xeb4034])
        let faint = try Self.frame([Self.layer([20, 40, 60, 1])])
        XCTAssertEqual(MatrixRaster.make(panel: try Self.panel(), cells: [], layers: faint.layers).pixels[0], 0x14283c)
    }

    func testClippingNeverWrapsAndTinyPanelsStillRenderPixels() throws {
        let frame = try Self.frame([
            Self.layer([1, 0, 0, 255, 2, 0, 0, 255, 3, 0, 0, 255, 4, 0, 0, 255], x: -1, y: -1, width: 2, height: 2),
            Self.layer([0, 1, 0, 255, 0, 2, 0, 255, 0, 3, 0, 255, 0, 4, 0, 255], x: 1, y: 1, width: 2, height: 2),
            Self.layer([255, 0, 0, 255], x: Int.max),
            Self.layer([255, 0, 0, 255], y: Int.min),
            Self.layer([255, 0, 0, 255], x: Int.min, y: Int.max),
        ])
        XCTAssertEqual(MatrixRaster.make(panel: try Self.panel(width: 2, height: 2), cells: [], layers: frame.layers).pixels,
                       [0x040000, 0, 0, 0x000100])
    }

    func testMonochromeUsesWeightedThresholdAndTransparentPixelsKeepText() throws {
        let frame = try Self.frame([Self.layer([
            127, 127, 127, 255, 128, 128, 128, 1, 255, 0, 0, 255,
            0, 255, 0, 255, 0, 0, 0, 0,
        ], width: 5)])
        let raster = MatrixRaster.make(panel: try Self.panel(mono: "#ffb000"), cells: [[.color(.red)]], layers: frame.layers)
        XCTAssertEqual(Array(raster.pixels.prefix(5)), [0, 0xffb000, 0, 0xffb000, 0xffb000])
    }

    func testMalformedLayersAreSkippedWithoutDroppingValidSiblingsOrText() throws {
        var invalidBase64 = Self.layer([255, 0, 0, 255]); invalidBase64["rgba"] = "!!!!"
        var invalidCoordinate = Self.layer([255, 0, 0, 255]); invalidCoordinate["x"] = "0"
        let frame = try Self.frame([
            NSNull(), "not a layer", ["width": 1], invalidBase64, invalidCoordinate,
            Self.layer([255, 0, 0], width: 1), Self.layer([255, 0, 0, 255, 0], width: 1),
            Self.layer([], width: 0), Self.layer([], height: -1),
            Self.layer([], width: 257), Self.layer([], height: Int.max),
            Self.layer([0, 255, 0, 255]),
        ], characters: [[1]])
        let raster = MatrixRaster.make(panel: try Self.panel(), cells: [[.character("A")]], layers: frame.layers)
        XCTAssertEqual(raster.pixels[0], 0x00ff00)
        XCTAssertEqual(raster.pixels[1], 0xffffff)
        XCTAssertEqual(raster.text, "A")
        XCTAssertEqual(frame.layers.count, 1)
    }

    func testLayerCountIsBoundedAndMissingNullOrWrongContainerIsLegacy() throws {
        let layers = Array(repeating: Self.layer([255, 0, 0, 255]), count: 64) + [Self.layer([0, 0, 255, 255])]
        let frame = try Self.frame(layers)
        XCTAssertEqual(MatrixRaster.make(panel: try Self.panel(width: 1, height: 1), cells: [], layers: frame.layers).pixels, [0xff0000])
        for raw in ["null", "{}", "\"bad\"", "[]"] {
            let legacy = try JSONDecoder().decode(PanelFrame.self, from: Data("{\"rows\":1,\"cols\":1,\"layers\":\(raw)}".utf8))
            XCTAssertEqual(legacy, try Self.frame())
        }
    }

    func testMaximumBitmapDimensionsAreAccepted() throws {
        var bytes = [UInt8](repeating: 0, count: 256 * 256 * 4)
        bytes.replaceSubrange((bytes.count - 4)..<bytes.count, with: [12, 34, 56, 255])
        let frame = try Self.frame([Self.layer(bytes, width: 256, height: 256)])
        let raster = MatrixRaster.make(panel: try Self.panel(width: 256, height: 256), cells: [], layers: frame.layers)
        XCTAssertEqual(raster.pixels.last, 0x0c2238)
        XCTAssertEqual(raster.pixels.filter { $0 != 0 }.count, 1)
    }

    func testPreviewPixelsAndCacheIdentityFollowPixelOnlyUpdatesAndRemoval() throws {
        let red = PanelPreview.make(from: try Self.frame([Self.layer([255, 0, 0, 255])]), code62: .degree)
        let blue = PanelPreview.make(from: try Self.frame([Self.layer([0, 0, 255, 255])]), code62: .degree)
        let empty = PanelPreview.make(from: try Self.frame(), code62: .degree)
        XCTAssertNotEqual(red, blue)
        XCTAssertNotEqual(blue, empty)
        let panel = try Self.panel(width: 1, height: 1)
        for (preview, expected) in [(red, UInt32(0xff0000)), (blue, UInt32(0x0000ff)), (empty, UInt32(0))] {
            XCTAssertEqual(MatrixRaster.make(panel: panel, cells: preview.cells,
                richCells: preview.richCells, layers: preview.layers).pixels, [expected])
        }
    }
}

final class PixelLayerStoreTests: XCTestCase {
    func testStoreRetainsPixelsDuringOutageAndClearsThemWhenRemoved() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let panel = try PixelLayerTests.panel(width: 1, height: 1)
        StubURLProtocol.enqueue(.json(String(decoding: try JSONEncoder().encode(panel), as: UTF8.self)), for: "/api/panel/1")
        let red = #"{"rows":1,"cols":1,"layers":[{"x":0,"y":0,"width":1,"height":1,"rgba":"/wAA/w=="}]}"#
        let blue = #"{"rows":1,"cols":1,"layers":[{"x":0,"y":0,"width":1,"height":1,"rgba":"AAD//w=="}]}"#
        StubURLProtocol.enqueue(.json(red), for: "/frame")
        StubURLProtocol.enqueue(.json(blue), for: "/frame")
        StubURLProtocol.enqueue(.json("{}", status: 503), for: "/frame")
        StubURLProtocol.enqueue(.json(#"{"rows":1,"cols":1}"#), for: "/frame")
        let store = PanelStore(client: FiestaClient(baseURL: URL(string: "http://host:4420")!,
            session: StubURLProtocol.makeSession()), ref: "1", frameInterval: 0.01, configInterval: 60)
        defer { store.stop() }
        var snapshots: [PanelSnapshot] = []
        for await snapshot in store.snapshots() {
            snapshots.append(snapshot)
            if snapshots.count == 4 { break }
        }
        XCTAssertEqual(snapshots.count, 4)
        let pixels = snapshots.map { MatrixRaster.make(panel: panel, cells: $0.cells, richCells: $0.richCells, layers: $0.layers).pixels[0] }
        XCTAssertEqual(pixels, [0xff0000, 0x0000ff, 0x0000ff, 0])
        XCTAssertEqual(snapshots.map(\.connection), [.live, .live, .stale, .live])
        XCTAssertNotEqual(snapshots[0], snapshots[1])
        XCTAssertNotEqual(snapshots[1], snapshots[3])
        XCTAssertEqual(snapshots[0].spokenContent, "Coloured pixels, no text")
        XCTAssertEqual(snapshots[3].spokenContent, BoardSpeech.blank)
    }
}
