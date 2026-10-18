import XCTest
@testable import FiestaBoardTV

final class PanelSettingsDraftTests: XCTestCase {
    private func panel(_ fields: [String: Any] = [:]) throws -> Panel {
        var json = try JSONSerialization.jsonObject(with: Data(Fixtures.panelJSON.utf8)) as! [String: Any]
        json.merge(fields) { _, new in new }
        return try JSONDecoder().decode(Panel.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testRenameDoesNotEnableSharedMatrixSizingOrOverwriteOtherSettings() throws {
        let original = try panel(["render_style": "led_matrix", "matrix_sizing": NSNull(), "matrix_pitch_mm": 6])
        var draft = PanelSettingsDraft(panel: original)
        XCTAssertTrue(try draft.patch().body.isEmpty)
        draft.name = "Kitchen"
        XCTAssertEqual(try draft.patch().body as NSDictionary, ["name": "Kitchen"] as NSDictionary)
        draft.diagonalText = "65.000"
        XCTAssertEqual(try draft.patch().body.count, 1, "numeric formatting is not a change")
    }

    func testCodableRoundTripPreservesSupportForUnsetSharedSizing() throws {
        let original = try panel(["matrix_sizing": NSNull(), "matrix_pitch_mm": 6])
        let decoded = try JSONDecoder().decode(Panel.self, from: JSONEncoder().encode(original))
        XCTAssertTrue(decoded.supportsMatrixSettings)
        var draft = PanelSettingsDraft(panel: decoded)
        draft.matrixSizing = .trueSize
        XCTAssertNoThrow(try draft.patch())
        let legacy = try JSONDecoder().decode(Panel.self, from: JSONEncoder().encode(panel()))
        XCTAssertFalse(legacy.supportsMatrixSettings)
    }

    func testSharedSizingCanBeResetWithoutClearingPitchOrScreenSize() throws {
        var draft = PanelSettingsDraft(panel: try panel(["matrix_sizing": "true_size", "matrix_pitch_mm": 5]))
        draft.matrixSizing = nil
        XCTAssertEqual(try draft.patch().body as NSDictionary, ["matrix_sizing": NSNull()] as NSDictionary)
    }

    func testRejectsInvalidNumbersNamesAndTimesBeforeCreatingPatch() throws {
        let original = try panel(["matrix_sizing": NSNull(), "matrix_pitch_mm": 6])
        for input in ["", "NaN", "inf", "-1", "201"] {
            var draft = PanelSettingsDraft(panel: original)
            draft.diagonalText = input
            XCTAssertThrowsError(try draft.patch(), input)
        }
        for (key, value) in [(\PanelSettingsDraft.aspectWidthText, "0"), (\.aspectHeightText, "101"),
                             (\.calibrationText, "1.16"), (\.pitchText, "0"), (\.name, "   "),
                             (\.dimStart, "24:00"), (\.dimEnd, "7:00"), (\.dimStart, "22:60"), (\.dimStart, "22:00\n")] {
            var draft = PanelSettingsDraft(panel: original)
            draft[keyPath: key] = value
            XCTAssertThrowsError(try draft.patch(), value)
        }
    }

    func testSendsOnlyChangedFieldsIncludingCompleteDimWindow() throws {
        var draft = PanelSettingsDraft(panel: try panel(["render_style": "led_matrix", "matrix_sizing": NSNull(), "matrix_pitch_mm": 6]))
        draft.animationsEnabled = true
        draft.dimStart = "23:15"
        draft.backdrop = "dark"
        draft.matrixSizing = .fitPanel
        XCTAssertEqual(try draft.patch().body as NSDictionary, [
            "animations_enabled": true, "backdrop": "dark", "matrix_sizing": "fit_panel",
            "auto_dim": ["enabled": true, "start": "23:15", "end": "07:00"]
        ] as NSDictionary)
    }

    func testOldServerCannotPretendToSaveMatrixSettings() throws {
        var draft = PanelSettingsDraft(panel: try panel(["render_style": "led_matrix"]))
        draft.matrixSizing = .trueSize
        XCTAssertThrowsError(try draft.patch())
        var supported = PanelSettingsDraft(panel: try panel(["matrix_sizing": NSNull(), "matrix_pitch_mm": 6]))
        supported.matrixSizing = .trueSize
        XCTAssertThrowsError(try supported.patch().verifyApplied(to: panel()), "unknown fields may be silently ignored by old servers")
        XCTAssertNoThrow(try supported.patch().verifyApplied(to: panel(["matrix_sizing": "true_size", "matrix_pitch_mm": 6])))
    }

    func testPhysicalMatrixGeometryUsesActualViewportAndCalibrationWithoutCropping() throws {
        let panel = try panel(["render_style": "led_matrix", "matrix_sizing": "true_size", "matrix_pitch_mm": 5,
                               "screen_diagonal_inches": 55, "screen_aspect_w": 4, "screen_aspect_h": 3,
                               "calibration_scale": 1.1])
        let layout = try XCTUnwrap(MatrixLayout.make(width: 100, height: 50, viewportWidth: 1920, viewportHeight: 1080,
                                                    presentation: XCTUnwrap(panel.matrixPresentation)))
        // TV pixels determine physical scale; the configured aspect shapes the source grid.
        XCTAssertEqual(layout.pitch, 8.6728628743, accuracy: 0.000001)
        let huge = try XCTUnwrap(MatrixLayout.make(width: 720, height: 192, viewportWidth: 1920, viewportHeight: 1080,
                                                  presentation: XCTUnwrap(panel.matrixPresentation)))
        XCTAssertEqual(huge.pitch, 1920.0 / 720, accuracy: 0.000001)
        XCTAssertGreaterThanOrEqual(huge.originX, 0)
        XCTAssertLessThanOrEqual(huge.originY + 192 * huge.pitch, 1080)
    }

    func testSharedCalibrationAppliesToLocalSizingWithoutReplacingLocalScreenOrPitch() throws {
        let panel = try panel(["render_style": "led_matrix", "matrix_sizing": NSNull(),
                               "matrix_pitch_mm": 6, "calibration_scale": 1.1])
        let local = MatrixPresentation(sizing: .trueSize, diagonalInches: 75, pitchMillimeters: 5)
        let resolved = panel.effectiveMatrixPresentation(fallback: local)
        XCTAssertEqual(resolved.sizing, .trueSize)
        XCTAssertEqual(resolved.diagonalInches, 75)
        XCTAssertEqual(resolved.pitchMillimeters, 5)
        XCTAssertEqual(resolved.calibrationScale, 1.1)
    }

    func testOldLocalPresentationDefaultsNewPhysicalFields() throws {
        let decoded = try JSONDecoder().decode(MatrixPresentation.self, from: Data(#"{"sizing":"trueSize","diagonalInches":65,"pitchMillimeters":5}"#.utf8))
        XCTAssertEqual(decoded.calibrationScale, 1)
    }

    func testListAndPatchPanelWithoutModelStillContainsResizedCellGrid() throws {
        let panel = try panel(["render_style": "led_matrix", "cols": 120, "rows": 24])
        XCTAssertEqual(panel.matrixDisplay.width, 720)
        XCTAssertEqual(panel.matrixDisplay.height, 192)
    }

    func testResizedFiestaPanelContainsEveryCellAndPreservesDeviceAppearance() throws {
        let panel = try panel(["render_style": "led_matrix", "cols": 120, "rows": 24, "device_model_spec": [
            "id": "fiestapanel_led_matrix", "geometry": ["kind": "pixels", "width": 192, "height": 96],
            "appearance": ["pixelShape": "round"], "font": "5x7"
        ]])
        XCTAssertEqual(panel.matrixDisplay.width, 720)
        XCTAssertEqual(panel.matrixDisplay.height, 192)
        XCTAssertEqual(panel.matrixDisplay.appearance?.pixelShape, "round")
        XCTAssertNotNil(MatrixLayout.make(width: 720, height: 192, viewportWidth: 1920, viewportHeight: 1080, presentation: .init()))
    }
}
