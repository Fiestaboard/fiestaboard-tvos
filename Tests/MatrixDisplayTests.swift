import SwiftUI
import XCTest
@testable import FiestaBoardTV

final class MatrixDisplayTests: XCTestCase {
    @MainActor
    func testViewerFillsTVWithUnlitLEDsWithoutMovingTheMessage() throws {
        let panel = try Self.matrixPanel(width: 192, height: 96)
        let app = AppModel(connection: ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, credentials: InMemoryCredentialStore()))
        let model = ViewerModel(app: app, ref: panel.id,
                                signage: SignageSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        model.apply(PanelSnapshot(panel: panel, cells: [[.color(.red)]], rows: 1, cols: 1,
                                  connection: .live, dimmed: false, deleted: false))
        let image = RenderHarness.image(ViewerScreen(ref: panel.id, model: model).environment(app))
        for y in [5, 55, 1025, 1075] {
            let pixel = try XCTUnwrap(image.pixel(x: 5, y: y))
            XCTAssertEqual(Int(pixel.r), 26, accuracy: 1, "the old black bars should contain unlit LEDs")
            XCTAssertEqual(Int(pixel.a), 255)
        }
        let message = try XCTUnwrap(image.pixel(x: 5, y: 65))
        XCTAssertEqual(Int(message.r), 235, accuracy: 1, "the source pixels keep their position and color")
    }

    func testPhysicalLEDSpacingUsesFixedTVAspectAndPreservesTheWholePanel() throws {
        func layout(_ diagonal: Double, _ spacing: Double, width: Double = 1920, height: Double = 1080) throws -> MatrixLayout {
            try XCTUnwrap(MatrixLayout.make(width: 192, height: 96, viewportWidth: width, viewportHeight: height,
                presentation: MatrixPresentation(sizing: .trueSize, diagonalInches: diagonal, pitchMillimeters: spacing)))
        }
        let smallTV = try layout(55, 5)
        let largeTV = try layout(75, 5)
        // A 55-inch 16:9 screen is 1217.5908 mm wide: a 5 mm LED pitch is 7.88442 points at 1080p.
        XCTAssertEqual(smallTV.pitch, 7.88442, accuracy: 0.0001)
        XCTAssertEqual(largeTV.pitch, 5.78191, accuracy: 0.0001)
        XCTAssertEqual(try layout(55, 5, width: 3840, height: 2160).pitch, smallTV.pitch * 2, accuracy: 0.0001)
        let oversized = try layout(32, 20)
        XCTAssertEqual(oversized.pitch, 10, "a panel larger than the TV must fit without cropping its message")
    }

    func testFillAndFitShareSourceGeometryButOnlyFillExtendsTheField() throws {
        for (width, height) in [(192, 96), (96, 192)] {
            let fit = try XCTUnwrap(MatrixLayout.make(width: width, height: height, viewportWidth: 1920, viewportHeight: 1080,
                                                     presentation: .init(sizing: .fitPanel)))
            let fill = try XCTUnwrap(MatrixLayout.make(width: width, height: height, viewportWidth: 1920, viewportHeight: 1080,
                                                      presentation: .init(sizing: .fillTV)))
            XCTAssertEqual(fit.pitch, fill.pitch)
            XCTAssertEqual(fit.originX, fill.originX)
            XCTAssertEqual(fit.originY, fill.originY)
            XCTAssertEqual(fit.rows, 0..<height)
            XCTAssertEqual(fit.columns, 0..<width)
            XCTAssertLessThanOrEqual(fill.originX + Double(fill.columns.lowerBound) * fill.pitch, 0)
            XCTAssertGreaterThanOrEqual(fill.originX + Double(fill.columns.upperBound) * fill.pitch, 1920)
            XCTAssertLessThanOrEqual(fill.originY + Double(fill.rows.lowerBound) * fill.pitch, 0)
            XCTAssertGreaterThanOrEqual(fill.originY + Double(fill.rows.upperBound) * fill.pitch, 1080)
        }
        XCTAssertNil(MatrixLayout.make(width: 0, height: 96, viewportWidth: 1920, viewportHeight: 1080, presentation: .init()))
        XCTAssertNil(MatrixLayout.make(width: 192, height: 96, viewportWidth: .infinity, viewportHeight: 1080, presentation: .init()))
    }

    func testMatrixDriftNeverCropsSourceEdgesInAnySizingMode() throws {
        for mode in MatrixSizing.allCases {
            for shift in [-8.0, 8.0] {
                let layout = try XCTUnwrap(MatrixLayout.make(width: 192, height: 96, viewportWidth: 1920, viewportHeight: 1080,
                    presentation: .init(sizing: mode, diagonalInches: 32, pitchMillimeters: 20),
                    drift: BoardOffset(x: shift, y: shift)))
                XCTAssertEqual(layout.originX, 0, "no horizontal margin remains at fit scale")
                XCTAssertEqual(layout.originY, 60 + shift, "vertical movement still works within the margin")
                XCTAssertLessThanOrEqual(layout.originX + 192 * layout.pitch, 1920)
                XCTAssertLessThanOrEqual(layout.originY + 96 * layout.pitch, 1080)
            }
        }
    }

    @MainActor
    func testFillPreservesRoundLEDsAndCoversEdgesWhileDrifting() throws {
        let panel = try Self.panel(["render_style": "led_matrix", "device_model_spec": [
            "geometry": ["kind": "pixels", "width": 192, "height": 96],
            "appearance": ["pixelShape": "round"]]])
        let raster = MatrixRaster.make(panel: panel, cells: [[.color(.red)]])
        let image = RenderHarness.image(MatrixCanvas(raster: raster, display: panel.matrixDisplay,
            presentation: .init(sizing: .fillTV), drift: BoardOffset(x: 2, y: 2)))
        XCTAssertEqual(Int(try XCTUnwrap(image.pixel(x: 5, y: 7)).r), 26, accuracy: 1)
        XCTAssertLessThan(try XCTUnwrap(image.pixel(x: 1, y: 3)).r, 5, "round corners stay substrate")
        XCTAssertEqual(Int(try XCTUnwrap(image.pixel(x: 5, y: 67)).r), 235, accuracy: 1)
        XCTAssertEqual(Int(try XCTUnwrap(image.pixel(x: 1915, y: 1077)).r), 26, accuracy: 1)
    }

    @MainActor
    func testSharedPanelSizingFollowsConfigRefreshAndLegacyUsesLocalSettings() throws {
        let signage = SignageSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        signage.matrixPresentation = .init(sizing: .fitPanel, diagonalInches: 65, pitchMillimeters: 8)
        let app = AppModel(connection: ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, credentials: InMemoryCredentialStore()))
        let viewer = ViewerModel(app: app, ref: "p1", signage: signage)
        func apply(_ fields: [String: Any]) throws {
            viewer.apply(PanelSnapshot(panel: try Self.panel(fields), cells: [], rows: 12, cols: 29,
                connection: .live, dimmed: false, deleted: false))
        }
        try apply(["render_style": "led_matrix", "matrix_sizing": "true_size", "matrix_pitch_mm": 5,
                   "screen_diagonal_inches": 75, "screen_aspect_w": 21])
        XCTAssertEqual(viewer.matrixPresentation, .init(sizing: .trueSize, diagonalInches: 75, pitchMillimeters: 5))
        try apply(["render_style": "led_matrix", "matrix_sizing": "fill_tv"])
        XCTAssertEqual(viewer.matrixPresentation.sizing, .fillTV)
        try apply(["render_style": "led_matrix"])
        XCTAssertEqual(viewer.matrixPresentation, signage.matrixPresentation)
        try apply(["render_style": "led_matrix", "matrix_sizing": "future_mode"])
        XCTAssertEqual(viewer.matrixPresentation, signage.matrixPresentation)
    }

    @MainActor
    func testViewerAppliesSharedCalibrationWhileFollowingLocalMatrixSizing() throws {
        let signage = SignageSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        signage.matrixPresentation = .init(sizing: .trueSize, diagonalInches: 75, pitchMillimeters: 5)
        let app = AppModel(connection: ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, credentials: InMemoryCredentialStore()))
        let viewer = ViewerModel(app: app, ref: "p1", signage: signage)
        let panel = try Self.panel(["render_style": "led_matrix", "matrix_sizing": NSNull(),
                                    "matrix_pitch_mm": 6, "calibration_scale": 1.1])
        viewer.apply(PanelSnapshot(panel: panel, cells: [], rows: 12, cols: 30,
                                   connection: .live, dimmed: false, deleted: false))
        XCTAssertEqual(viewer.matrixPresentation, .init(sizing: .trueSize, diagonalInches: 75,
                                                       pitchMillimeters: 5, calibrationScale: 1.1))
    }

    static func matrixPanel(width: Int = 5, height: Int = 7, font: String = "5x7", mono: String? = nil) throws -> Panel {
        var spec: [String: Any] = ["geometry": ["kind": "pixels", "width": width, "height": height], "font": font]
        if let mono { spec["color"] = ["kind": "monochrome", "color": mono] }
        return try panel(["render_style": "led_matrix", "device_model_spec": spec])
    }

    func testExactBitmapPixelsForBothFontsAndRichCase() throws {
        let small = MatrixRaster.make(panel: try Self.matrixPanel(width: 3, height: 5, font: "3x5"), cells: [[.character("A")]])
        XCTAssertEqual(small.pixels, [".#.", "#.#", "###", "#.#", "#.#"].joined().map { $0 == "#" ? 0xffffff : 0 })
        let upper = MatrixRaster.make(panel: try Self.matrixPanel(), cells: [[.character("A")]])
        XCTAssertEqual(upper.pixels, ".###.#...##...#######...##...##...#".map { $0 == "#" ? 0xffffff : 0 })
        let lower = MatrixRaster.make(panel: try Self.matrixPanel(), cells: [[.character("A")]], richCells: [[MatrixCell(type: "char", value: "a", color: "red")]])
        XCTAssertEqual(lower.pixels, "...........###.....#.#####...#.####".map { $0 == "#" ? 0xeb4034 : 0 })
    }

    func testBlocksJoinGuttersAndBlackTextCutsOutTheBackground() throws {
        let cell = MatrixCell(type: "char", value: "A", color: "black", background: "white")
        let raster = MatrixRaster.make(panel: try Self.matrixPanel(width: 11), cells: [], richCells: [[cell, cell]])
        XCTAssertEqual(raster.pixels[0], 0xffffff)
        XCTAssertEqual(raster.pixels[1], 0)
        XCTAssertEqual(raster.pixels[5], 0xffffff, "same block bridges the gutter")
        let mono = MatrixRaster.make(panel: try Self.matrixPanel(mono: "#ffb000"), cells: [], richCells: [[cell]])
        XCTAssertEqual(mono.pixels[0], 0xffb000)
        XCTAssertEqual(mono.pixels[1], 0)
    }

    func testTilesHeartIconsAndPadding() throws {
        let panel = try Self.matrixPanel(width: 11)
        let tiles = MatrixRaster.make(panel: panel, cells: [[.color(.red), .color(.black), .color(.blue)]])
        XCTAssertEqual(tiles.pixels.count, 77)
        XCTAssertEqual(tiles.pixels[0], 0xeb4034)
        XCTAssertEqual(tiles.pixels[5], 0)
        XCTAssertEqual(tiles.pixels[6], 0)
        let heart = MatrixRaster.make(panel: panel, cells: [[.character("♥")]])
        XCTAssertTrue(heart.pixels.contains(0xeb4034))
        XCTAssertEqual(Set(heart.pixels), [0, 0xeb4034])
        let icon = MatrixRaster.make(panel: panel, cells: [], richCells: [[MatrixCell(type: "char", value: " ", icon: "sun")]])
        XCTAssertTrue(icon.pixels.contains(0xf8e71c))
        XCTAssertEqual(Set(icon.pixels), [0, 0xf8e71c])
        let tiny = MatrixRaster.make(panel: try Self.matrixPanel(width: 1, height: 1), cells: [[.character("A")]])
        XCTAssertEqual(tiny.pixels, [0])
    }

    func testUnknownIconsUseWireFallback() throws {
        let panel = try Self.matrixPanel()
        let tile = MatrixRaster.make(panel: panel, cells: [], richCells: [[MatrixCell(type: "color", code: "65", icon: "future-icon")]])
        XCTAssertEqual(Set(tile.pixels), [0xf8e71c])
        let letter = MatrixRaster.make(panel: panel, cells: [], richCells: [[MatrixCell(type: "char", value: "A", color: "red", icon: "future-icon")]])
        XCTAssertEqual(letter.pixels, ".###.#...##...#######...##...##...#".map { $0 == "#" ? 0xeb4034 : 0 })
    }

    func testMatrixSpeechReadsVisibleRichCellsButNotAnOutage() throws {
        let panel = try Self.matrixPanel(width: 11)
        let rich = [[MatrixCell(type: "char", value: "a"), MatrixCell(type: "char", value: " ", icon: "sun"), MatrixCell(type: "char", value: "Z")]]
        let raster = MatrixRaster.make(panel: panel, cells: [], richCells: rich)
        XCTAssertEqual(raster.spoken(message: nil), "a sun", "clip speech to the visible glyph grid")
        XCTAssertEqual(raster.spoken(message: "Server message"), "Server message")
        let live = PanelSnapshot(panel: panel, cells: [], rows: 1, cols: 3, connection: .live, dimmed: false, deleted: false, richCells: rich)
        XCTAssertEqual(live.spokenContent, "a sun")
        let stale = PanelSnapshot(panel: panel, cells: [[.character("X")]], rows: 1, cols: 1, connection: .stale, dimmed: false, deleted: false, richCells: rich)
        XCTAssertEqual(stale.spokenContent, "Disconnected. Showing the last frame.")
    }

    @MainActor
    func testRichOnlyCardReadsItsVisibleMessage() throws {
        let panel = try Self.matrixPanel()
        let preview = PanelPreview(rows: 1, cols: 1, cells: [], message: nil, richCells: [[MatrixCell(type: "char", value: "a")]])
        let card = PanelCard(panel: panel, preview: .ready(preview), action: {})
        XCTAssertEqual(card.subtitle, "a")
        XCTAssertTrue(card.accessibilityLabel.contains("Board reads: a"))
    }

    @MainActor
    func testDefaultSquarePixelsAndExplicitRoundAppearance() throws {
        let size = CGSize(width: 500, height: 700)
        for (appearance, square) in [([String: Any](), true), (["pixelShape": "round"], false)] {
            let panel = try Self.panel(["render_style": "led_matrix", "device_model_spec": [
                "geometry": ["kind": "pixels", "width": 5, "height": 7], "font": "5x7",
                "appearance": appearance
            ]])
            let raster = MatrixRaster.make(panel: panel, cells: [[.color(.red)]])
            let image = RenderHarness.image(MatrixCanvas(raster: raster, display: panel.matrixDisplay)
                .frame(width: size.width, height: size.height), size: size)
            let corner = try XCTUnwrap(image.pixel(x: 15, y: 15))
            if square { XCTAssertGreaterThan(corner.r, 200) }
            else { XCTAssertLessThan(corner.r, 40) }
            XCTAssertGreaterThan(try XCTUnwrap(image.pixel(x: 50, y: 50)).r, 200)
        }
    }

    @MainActor
    func testMatrixAppearanceUsesModelColorsAndDotRatio() throws {
        let panel = try Self.panel(["render_style": "led_matrix", "device_model_spec": [
            "geometry": ["kind": "pixels", "width": 5, "height": 7], "font": "5x7",
            "appearance": ["pixelShape": "square", "dotRatio": 0.5,
                           "offColor": "#123456", "substrateColor": "#abcdef"]
        ]])
        let raster = MatrixRaster.make(panel: panel, cells: [[.character("A")]])
        let size = CGSize(width: 500, height: 700)
        let image = RenderHarness.image(MatrixCanvas(raster: raster, display: panel.matrixDisplay)
            .frame(width: size.width, height: size.height), size: size)
        let off = try XCTUnwrap(image.pixel(x: 50, y: 50))
        XCTAssertEqual(Double(off.r), 0x12, accuracy: 1)
        XCTAssertEqual(Double(off.g), 0x34, accuracy: 1)
        XCTAssertEqual(Double(off.b), 0x56, accuracy: 1)
        let substrate = try XCTUnwrap(image.pixel(x: 15, y: 50))
        XCTAssertEqual(Double(substrate.r), 0xab, accuracy: 1)
        XCTAssertEqual(Double(substrate.g), 0xcd, accuracy: 1)
        XCTAssertEqual(Double(substrate.b), 0xef, accuracy: 1)
        XCTAssertGreaterThan(try XCTUnwrap(image.pixel(x: 150, y: 50)).r, 250)
    }

    /// Flat fills lose the lens and emitted light; these samples also catch
    /// an empty render and any glow spilling into the OLED surround.
    @MainActor
    func testLEDLightingPreservesCentersAndStaysInsideThePanel() throws {
        for shape in ["square", "round"] {
            let display = try JSONDecoder().decode(MatrixDisplay.self, from: Data(
                "{\"appearance\":{\"pixelShape\":\"\(shape)\"}}".utf8))
            let raster = MatrixRaster(width: 2, height: 1, pixels: [0xeb4034, 0], text: "")
            let size = CGSize(width: 200, height: 200)
            let image = RenderHarness.image(MatrixCanvas(raster: raster, display: display)
                .frame(width: size.width, height: size.height).background(Color.black), size: size)
            let center = try XCTUnwrap(image.pixel(x: 50, y: 100))
            XCTAssertEqual(Int(center.r), 235, accuracy: 1)
            XCTAssertEqual(Int(center.g), 64, accuracy: 1)
            XCTAssertEqual(Int(center.b), 52, accuracy: 1)
            let top = try XCTUnwrap(image.pixel(x: 50, y: 65))
            let bottom = try XCTUnwrap(image.pixel(x: 50, y: 135))
            XCTAssertGreaterThan(Int(top.r), Int(bottom.r) + 12, "the lens has restrained directional shading")
            let halo = try XCTUnwrap(image.pixel(x: 5, y: 100))
            XCTAssertGreaterThan(Int(halo.r), 3, "a lit lens emits a little light onto the substrate")
            XCTAssertLessThan(Int(halo.r), 40, "the halo must not fill in the grid")
            let unlit = try XCTUnwrap(image.pixel(x: 150, y: 100))
            XCTAssertEqual(Int(unlit.r), 26, accuracy: 1)
            let surround = try XCTUnwrap(image.pixel(x: 50, y: 48))
            XCTAssertEqual(Int(surround.r), 0)
            XCTAssertEqual(Int(surround.g), 0)
            XCTAssertEqual(Int(surround.b), 0)
        }
    }

    @MainActor
    func testAccessibilityRemovesLEDLightingWithoutErasingThePixels() throws {
        let raster = MatrixRaster(width: 2, height: 1, pixels: [0xeb4034, 0], text: "")
        let size = CGSize(width: 200, height: 100)
        // Accessibility environments are read-only. Exercise the painter's
        // no-lighting path, which both accessibility settings select.
        let view = Canvas { context, size in
            MatrixCanvas.paint(raster, display: .standard, size: size, lighting: false, in: &context)
        }.frame(width: size.width, height: size.height).background(Color.black)
        let image = RenderHarness.image(view, size: size)
        for y in [15, 50, 85] {
            let lit = try XCTUnwrap(image.pixel(x: 50, y: y))
            XCTAssertEqual(Int(lit.r), 235, accuracy: 1)
            XCTAssertEqual(Int(lit.g), 64, accuracy: 1)
            XCTAssertEqual(Int(lit.b), 52, accuracy: 1)
        }
        XCTAssertEqual(try XCTUnwrap(image.pixel(x: 5, y: 50)).r, 0)
    }

    @MainActor
    func testViewerAndPreviewRenderMatrixAndIgnoreFlapSizing() throws {
        let panel = try Self.matrixPanel()
        let app = AppModel(connection: ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, credentials: InMemoryCredentialStore()))
        // Rendering must not depend on physical-size preferences left by a
        // simulator user or a remote-navigation test.
        let signage = SignageSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let model = ViewerModel(app: app, ref: panel.id, signage: signage)
        model.sizing = .trueScale
        model.apply(PanelSnapshot(panel: panel, cells: [[.color(.red)]], rows: 1, cols: 1, connection: .live, dimmed: false, deleted: false))
        model.considerResizeOffer(for: CGSize(width: 1920, height: 1080))
        XCTAssertFalse(model.resizeOfferVisible)
        let preview = PanelPreview(rows: 1, cols: 1, cells: [[.color(.red)]], message: nil)
        let size = CGSize(width: 500, height: 700)
        let card = RenderHarness.image(PanelPreviewBoard(panel: panel, preview: preview).frame(width: size.width, height: size.height), size: size)
        let viewer = RenderHarness.image(ViewerScreen(ref: panel.id, model: model).environment(app).frame(width: size.width, height: size.height), size: size)
        for rendered in [card, viewer] {
            let lit = try XCTUnwrap(rendered.pixel(x: 50, y: 50))
            XCTAssertGreaterThan(lit.r, 200)
            XCTAssertLessThan(lit.g, 100)
            let gap = try XCTUnwrap(rendered.pixel(x: 100, y: 50))
            XCTAssertLessThan(gap.r, 40, "square pixels keep a visible substrate gutter")
        }
        model.resizeOfferVisible = true
        model.apply(model.snapshot)
        XCTAssertFalse(model.resizeOfferVisible, "switching style dismisses an old flap offer")
    }

    static func panel(_ fields: [String: Any] = [:]) throws -> Panel {
        var json = try JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as! [String: Any]
        json.merge(fields) { _, new in new }
        return try JSONDecoder().decode(Panel.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testLegacyAndUnknownStylesFallBackToFlaps() throws {
        let legacy = try Self.panel()
        XCTAssertEqual(legacy.renderStyle, .splitFlap)
        XCTAssertFalse(legacy.supportsRenderStyle)
        let future = try Self.panel(["render_style": "future"])
        XCTAssertEqual(future.renderStyle, .splitFlap)
        XCTAssertTrue(future.supportsRenderStyle)
    }

    func testMatrixGeometryIsBoundedAndDefaultsWithoutAModel() throws {
        let panel = try Self.panel(["render_style": "led_matrix"])
        XCTAssertEqual(panel.matrixDisplay.width, 192)
        XCTAssertEqual(panel.matrixDisplay.height, 96)
        let bounded = try Self.panel(["render_style": "led_matrix", "device_model_spec": [
            "geometry": ["kind": "pixels", "width": 4_000_000_000, "height": -10], "font": "unknown"
        ]])
        XCTAssertEqual(bounded.matrixDisplay.width, MatrixDisplay.maxPixelDimension)
        XCTAssertEqual(bounded.matrixDisplay.height, 1)
        XCTAssertEqual(bounded.matrixDisplay.font, "5x7")
    }

    func testRichOnlyFramePreservesColorsAndClipsToDeclaredGrid() throws {
        let frame = try JSONDecoder().decode(PanelFrame.self, from: Data(#"{"rows":1,"cols":1,"characters":null,"cells":[[{"type":"char","value":"a","color":"red","background":"white","icon":"heart"},{"type":"char","value":"B"}],[{"type":"char","value":"C"}]]}"#.utf8))
        XCTAssertEqual(frame.richCells?.count, 1)
        XCTAssertEqual(frame.richCells?.first?.count, 1)
        XCTAssertEqual(frame.richCells?.first?.first?.value, "a")
        XCTAssertEqual(frame.richCells?.first?.first?.color, "red")
        XCTAssertEqual(PanelPreview.make(from: frame, code62: .degree).richCells, frame.richCells)
    }

    func testStylePatchSendsOnlyTheRequestedField() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        let panel = try Self.panel(["render_style": "led_matrix"])
        let data = try JSONEncoder().encode(panel)
        StubURLProtocol.enqueue(.json("{\"panel\":\(String(decoding: data, as: UTF8.self))}"), for: "/api/panels/")
        let client = FiestaClient(baseURL: URL(string: "http://host:4420")!, session: StubURLProtocol.makeSession())
        _ = try await client.updatePanel(id: panel.id, renderStyle: .ledMatrix)
        let body = try XCTUnwrap(StubURLProtocol.requests.last?.body)
        let fields = try JSONSerialization.jsonObject(with: body) as! [String: String]
        XCTAssertEqual(fields, ["render_style": "led_matrix"])
    }

    func testRichFrameSurvivesAnOutageAndClearsSpeech() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.enqueue(.json(Fixtures.panelJSON), for: "/api/panel/1")
        StubURLProtocol.enqueue(.json(#"{"rows":1,"cols":1,"characters":null,"message":"A","cells":[[{"type":"char","value":"A","color":"red"}]]}"#), for: "/frame")
        let store = PanelStore(client: FiestaClient(baseURL: URL(string: "http://host:4420")!, session: StubURLProtocol.makeSession()), ref: "1", frameInterval: 0.01)
        defer { store.stop() }
        var count = 0
        for await snapshot in store.snapshots() {
            count += 1
            if snapshot.connection == .stale {
                XCTAssertEqual(snapshot.richCells?.first?.first?.color, "red")
                XCTAssertNil(snapshot.message)
                return
            }
            if count > 5 { break }
        }
        XCTFail("No stale snapshot")
    }

    func testPanelPreservesLEDStyleFromTheAdditiveContract() throws {
        let json = Fixtures.panelJSON.replacingOccurrences(of: "\"backdrop\":\"wall\"",
            with: "\"render_style\":\"led_matrix\",\"backdrop\":\"wall\"")
        let panel = try JSONDecoder().decode(Panel.self, from: Data(json.utf8))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(panel)) as! [String: Any]
        XCTAssertEqual(encoded["render_style"] as? String, "led_matrix")
    }
}
