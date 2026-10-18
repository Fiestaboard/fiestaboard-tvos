import Foundation

/// An editor snapshot. Empty and malformed input stays visible until corrected.
struct PanelSettingsDraft: Equatable {
    let original: Panel
    var name: String
    var diagonalText: String
    var aspectWidthText: String
    var aspectHeightText: String
    var calibrationText: String
    var animationsEnabled: Bool
    var renderStyle: PanelRenderStyle
    var matrixSizing: MatrixSizing?
    var pitchText: String
    var backdrop: String
    var dimEnabled: Bool
    var dimStart: String
    var dimEnd: String

    init(panel: Panel) {
        original = panel
        name = panel.name
        diagonalText = String(panel.screenDiagonalInches)
        aspectWidthText = String(panel.screenAspectW)
        aspectHeightText = String(panel.screenAspectH)
        calibrationText = String(panel.calibrationScale)
        animationsEnabled = panel.animationsEnabled
        renderStyle = panel.renderStyle
        matrixSizing = panel.matrixSizing
        pitchText = String(panel.matrixPitchMillimeters ?? 6)
        backdrop = panel.backdrop
        dimEnabled = panel.autoDim.enabled
        dimStart = panel.autoDim.start
        dimEnd = panel.autoDim.end
    }

    func patch() throws -> PanelSettingsPatch {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100).contains(trimmedName.count) else {
            throw PanelSettingsError.invalid("Enter a panel name from 1 to 100 characters.")
        }
        func number(_ text: String, _ range: ClosedRange<Double>, _ label: String) throws -> Double {
            guard let value = Double(text), value.isFinite, range.contains(value) else {
                throw PanelSettingsError.invalid("Enter \(label) from \(range.lowerBound) to \(range.upperBound).")
            }
            return value
        }
        let diagonal = try number(diagonalText, 3...200, "a screen size in inches")
        let aspectW = try number(aspectWidthText, 1...100, "an aspect width")
        let aspectH = try number(aspectHeightText, 1...100, "an aspect height")
        let calibration = try number(calibrationText, 0.85...1.15, "a calibration scale")
        let pitch = try number(pitchText, 1...20, "LED spacing in millimeters")
        func validTime(_ value: String) -> Bool {
            value.range(of: #"^([01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil
        }
        guard validTime(dimStart), validTime(dimEnd) else {
            throw PanelSettingsError.invalid("Enter dimming times as HH:MM using the 24-hour clock, for example 22:00.")
        }
        var body: [String: Any] = [:]
        if name != original.name, trimmedName != original.name { body["name"] = trimmedName }
        if diagonal != original.screenDiagonalInches { body["screen_diagonal_inches"] = diagonal }
        if aspectW != original.screenAspectW { body["screen_aspect_w"] = aspectW }
        if aspectH != original.screenAspectH { body["screen_aspect_h"] = aspectH }
        if calibration != original.calibrationScale { body["calibration_scale"] = calibration }
        if animationsEnabled != original.animationsEnabled { body["animations_enabled"] = animationsEnabled }
        if renderStyle != original.renderStyle {
            guard original.supportsRenderStyle else { throw PanelSettingsError.unsupported }
            body["render_style"] = renderStyle.rawValue
        }
        if matrixSizing != original.matrixSizing {
            guard original.supportsMatrixSettings else { throw PanelSettingsError.unsupported }
            body["matrix_sizing"] = matrixSizing.map { $0.serverValue as Any } ?? NSNull()
        }
        if pitch != (original.matrixPitchMillimeters ?? 6) {
            guard original.supportsMatrixSettings else { throw PanelSettingsError.unsupported }
            body["matrix_pitch_mm"] = pitch
        }
        if backdrop != original.backdrop {
            guard ["wall", "dark", "none"].contains(backdrop) else { throw PanelSettingsError.invalid("Choose a web viewer backdrop.") }
            body["backdrop"] = backdrop
        }
        let dim = AutoDim(enabled: dimEnabled, start: dimStart, end: dimEnd)
        if dim != original.autoDim {
            body["auto_dim"] = ["enabled": dimEnabled, "start": dimStart, "end": dimEnd]
        }
        return PanelSettingsPatch(body: body)
    }
}

enum PanelSettingsError: LocalizedError {
    case invalid(String)
    case unsupported
    case notApplied

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .unsupported: return "This board does not support these shared display settings. Update FiestaBoard to save them."
        case .notApplied: return "The board did not confirm all requested changes. Some settings may have saved. Your draft is kept; update FiestaBoard if this continues."
        }
    }
}

/// Fields are created only by the validated draft; explicit null resets shared sizing.
struct PanelSettingsPatch {
    let body: [String: Any]

    func verifyApplied(to panel: Panel) throws {
        var actual = try JSONSerialization.jsonObject(with: JSONEncoder().encode(panel)) as! [String: Any]
        // Optional Codable values are normally omitted, but an explicit reset
        // must distinguish a supported null from an old server missing the field.
        if body.keys.contains("matrix_sizing") {
            guard panel.supportsMatrixSettings else { throw PanelSettingsError.unsupported }
            actual["matrix_sizing"] = panel.matrixSizing.map { $0.serverValue as Any } ?? NSNull()
        }
        for (key, value) in body {
            guard let returned = actual[key], NSDictionary(dictionary: [key: value]).isEqual(to: [key: returned]) else {
                throw PanelSettingsError.notApplied
            }
        }
    }
}
