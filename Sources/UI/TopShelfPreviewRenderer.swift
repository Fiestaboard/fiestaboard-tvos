import SwiftUI

/// Renders the same flap canvas as the viewer into a carousel poster.
@MainActor
enum TopShelfPreviewRenderer {
    static let size = CGSize(width: 1920, height: 1080)

    static func png(panel: Panel, frame: PanelFrame) -> Data? {
        guard frame.rows > 0, frame.cols > 0 else { return nil }
        let cells = frame.characters.map {
            BoardTables.cells(from: $0, code62: panel.effectiveCode62)
        } ?? Array(repeating: Array(repeating: BoardCell.blank, count: frame.cols),
                   count: frame.rows)
        guard let layout = try? BoardLayout.fitting(
            rows: frame.rows, cols: frame.cols, cells: cells,
            in: size, mode: .fit,
            diagonalInches: panel.screenDiagonalInches,
            calibration: panel.calibrationScale,
            colPitchIn: BoardGeometry.colPitchIn(deviceType: panel.deviceType)) else { return nil }

        let content = BoardCanvas(layout: layout, background: panel.backgroundColor)
            .frame(width: size.width, height: size.height)
            .background(Color.black)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }
}
