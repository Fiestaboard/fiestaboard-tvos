import Foundation

public enum PanelRenderStyle: String, Codable, CaseIterable, Sendable {
    case splitFlap = "split_flap"
    case ledMatrix = "led_matrix"
}

/// The LED update effect chosen on this Apple TV, independently of the panel.
public enum MatrixTransitionStyle: String, CaseIterable, Sendable, Codable {
    case characterWipe, rowScan, pixelDissolve, marquee

    public var label: String {
        switch self {
        case .characterWipe: return "Character wipe"
        case .rowScan: return "Row scan"
        case .pixelDissolve: return "Pixel dissolve"
        case .marquee: return "Stepped marquee"
        }
    }
}

public enum MatrixSizing: String, Codable, CaseIterable, Sendable {
    case fillTV, fitPanel, trueSize

    public var serverValue: String {
        switch self {
        case .fillTV: return "fill_tv"
        case .fitPanel: return "fit_panel"
        case .trueSize: return "true_size"
        }
    }

    public init?(serverValue: String?) {
        switch serverValue {
        case "fill_tv": self = .fillTV
        case "fit_panel": self = .fitPanel
        case "true_size": self = .trueSize
        default: return nil
        }
    }
}

/// Presentation never changes the source pixel grid. A shared panel setting can override the TV default.
public struct MatrixPresentation: Codable, Equatable, Sendable {
    public let sizing: MatrixSizing
    public let diagonalInches: Double
    public let pitchMillimeters: Double
    public let calibrationScale: Double

    public init(sizing: MatrixSizing = .fillTV, diagonalInches: Double = 55, pitchMillimeters: Double = 6, calibrationScale: Double = 1) {
        self.calibrationScale = calibrationScale.isFinite ? min(1.15, max(0.85, calibrationScale)) : 1
        self.sizing = sizing
        self.diagonalInches = diagonalInches.isFinite && diagonalInches > 0 ? min(200, max(3, diagonalInches)) : 55
        self.pitchMillimeters = pitchMillimeters.isFinite && pitchMillimeters > 0 ? min(20, max(1, pitchMillimeters)) : 6
    }

    private enum CodingKeys: String, CodingKey { case sizing, diagonalInches, pitchMillimeters, calibrationScale }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try fields.decodeIfPresent(String.self, forKey: .sizing)
        self.init(sizing: raw.flatMap(MatrixSizing.init(rawValue:)) ?? .fillTV,
                  diagonalInches: try fields.decodeIfPresent(Double.self, forKey: .diagonalInches) ?? 55,
                  pitchMillimeters: try fields.decodeIfPresent(Double.self, forKey: .pitchMillimeters) ?? 6,
                  calibrationScale: try fields.decodeIfPresent(Double.self, forKey: .calibrationScale) ?? 1)
    }
}

/// One uniform pitch keeps both square and circular LEDs physically proportional.
public struct MatrixLayout: Equatable, Sendable {
    public let pitch: Double
    public let originX: Double
    public let originY: Double
    public let columns: Range<Int>
    public let rows: Range<Int>

    public static func make(width: Int, height: Int, viewportWidth: Double, viewportHeight: Double,
                            presentation: MatrixPresentation, drift: BoardOffset = .zero) -> MatrixLayout? {
        guard width > 0, height > 0, width <= MatrixDisplay.maxPixelDimension, height <= MatrixDisplay.maxPixelDimension,
              viewportWidth.isFinite, viewportHeight.isFinite, viewportWidth > 0, viewportHeight > 0 else { return nil }
        let fit = min(viewportWidth / Double(width), viewportHeight / Double(height))
        let pitch: Double
        if presentation.sizing == .trueSize {
            // Actual viewport pixels determine physical scale. The configured
            // panel aspect determines its cell grid, not the TV's pixel aspect.
            let pointsPerMillimeter = hypot(viewportWidth, viewportHeight) / (presentation.diagonalInches * 25.4)
            pitch = min(fit, pointsPerMillimeter * presentation.pitchMillimeters * presentation.calibrationScale)
        } else {
            pitch = fit
        }
        let fill = presentation.sizing == .fillTV
        let marginX = max(0, (viewportWidth - Double(width) * pitch) / 2)
        let marginY = max(0, (viewportHeight - Double(height) * pitch) / 2)
        // Screen protection may use spare space, but must not push edge content off the TV.
        let x = marginX + (drift.x.isFinite ? min(marginX, max(-marginX, drift.x)) : 0)
        let y = marginY + (drift.y.isFinite ? min(marginY, max(-marginY, drift.y)) : 0)
        // Fill adds only unlit LEDs outside the source. It never stretches, crops or reflows the message.
        let columns = fill ? Int(floor(-x / pitch))..<Int(ceil((viewportWidth - x) / pitch)) : 0..<width
        let rows = fill ? Int(floor(-y / pitch))..<Int(ceil((viewportHeight - y) / pitch)) : 0..<height
        return MatrixLayout(pitch: pitch, originX: x, originY: y, columns: columns, rows: rows)
    }
}

/// The additive subset of the output model that a native matrix needs.
public struct MatrixDisplay: Codable, Equatable, Sendable {
    public struct Geometry: Codable, Equatable, Sendable {
        public let kind: String?
        public let width: Int?
        public let height: Int?
    }
    public struct Appearance: Codable, Equatable, Sendable {
        public let pixelShape: String?
        public let dotRatio: Double?
        public let offColor: String?
        public let substrateColor: String?
    }
    public struct ColorSpec: Codable, Equatable, Sendable {
        public let kind: String?
        public let color: String?
    }
    public static let maxPixelDimension = 2048
    public let id: String?
    public let geometry: Geometry?
    private let fontName: String?
    public let appearance: Appearance?
    public let color: ColorSpec?

    enum CodingKeys: String, CodingKey {
        case id, geometry, appearance, color
        case fontName = "font"
    }

    public static let standard = MatrixDisplay(id: "fiestapanel_led_matrix", geometry: nil, fontName: nil, appearance: nil, color: nil)
    public var width: Int { min(Self.maxPixelDimension, max(1, geometry?.kind == "pixels" ? geometry?.width ?? 192 : 192)) }
    public var height: Int { min(Self.maxPixelDimension, max(1, geometry?.kind == "pixels" ? geometry?.height ?? 96 : 96)) }
    public var font: String { fontName == "3x5" ? "3x5" : "5x7" }
    public var dotRatio: Double { min(1, max(0.1, appearance?.dotRatio ?? 0.82)) }

    /// Old servers may keep the original 192×96 device model after a resize.
    /// Expand FiestaPanel's own model so the full declared cell grid is drawn.
    func containingCellGrid(rows: Int?, columns: Int?) -> MatrixDisplay {
        guard id == "fiestapanel_led_matrix", let rows, let columns else { return self }
        let cols = min(PanelFrame.maxDimension, max(1, columns))
        let boundedRows = min(PanelFrame.maxDimension, max(1, rows))
        let pitchX = font == "3x5" ? 4 : 6
        let pitchY = font == "3x5" ? 6 : 8
        return MatrixDisplay(id: id, geometry: .init(kind: "pixels", width: max(width, cols * pitchX),
                                                     height: max(height, boundedRows * pitchY)),
                             fontName: fontName, appearance: appearance, color: color)
    }

}

/// Rich tokens are already parsed by the server. Preserve case and colors.
public struct MatrixCell: Codable, Equatable, Sendable {
    public let type: String
    public var value: String? = nil
    public var code: String? = nil
    public var color: String? = nil
    public var background: String? = nil
    public var icon: String? = nil
}
