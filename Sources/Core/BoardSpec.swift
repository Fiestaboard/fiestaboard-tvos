import Foundation

/// The cross-language rendering contract, decoded from Spec/board-spec.json.
///
/// This type deliberately mirrors the JSON rather than improving on it: the
/// file is the shared artifact, and a Swift-side reinterpretation would
/// defeat the point of having one.
public struct BoardSpec: Decodable, Sendable {

    public struct TileRatios: Decodable, Sendable {
        public let width: Double
        public let gutter: Double
        public let radius: Double
    }

    public struct Derived: Decodable, Sendable {
        public let colPitchIn: Double
        public let rowPitchIn: Double
        public let blockWidthIn: Double
        public let blockHeightIn: Double
    }

    public struct Code62Spec: Decodable, Sendable {
        public let degree: String
        public let heart: String
        public let heartDeviceTypes: [String]
    }

    public struct AutofitVector: Decodable, Sendable {
        public let name: String
        public let diagonal: Double
        public let aspectW: Double
        public let aspectH: Double
        public let notesWide: Int
        public let notesTall: Int
    }

    public struct ScreenDimensionVector: Decodable, Sendable {
        public let diagonal: Double
        public let aspectW: Double
        public let aspectH: Double
        public let widthIn: Double
        public let heightIn: Double
    }

    public struct Vectors: Decodable, Sendable {
        public let autofit: [AutofitVector]
        public let screenDimensions: [ScreenDimensionVector]
    }

    public let version: Int
    public let tileRatios: TileRatios
    public let noteUnitWidthIn: Double
    public let noteCols: Int
    public let noteRows: Int
    public let maxNotesPerAxis: Int
    public let derived: Derived
    public let maxFillStretch: Double
    public let characters: [String]
    public let undefinedCodes: [Int]
    public let code62: Code62Spec
    public let colors: [String: String]
    public let colorNames: [String: String]
    public let vectors: Vectors

    public static func load(from url: URL) throws -> BoardSpec {
        try JSONDecoder().decode(BoardSpec.self, from: Data(contentsOf: url))
    }
}
