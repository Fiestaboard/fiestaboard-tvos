import SwiftUI

/// Settings uses the viewer's renderers and the board's actual current content.
/// Calibration is hosted across the full TV viewport, with controls overlaid,
/// so physical sizing never derives from a small settings card.
struct SettingsPanelPreview: View {
    let panel: Panel
    let state: PanelPreviewState
    var calibrationScale: Double? = nil

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch state {
                case .loading:
                    ProgressView("Loading preview…")
                        .font(Fiesta.Text.caption)
                case .unavailable:
                    Label(panel.boardMissing ? "Board unavailable" : "Preview unavailable",
                          systemImage: "rectangle.slash")
                        .font(Fiesta.Text.caption)
                        .foregroundStyle(Fiesta.Colors.mutedForeground)
                case .ready(let preview):
                    ZStack {
                        board(preview, in: proxy.size)
                    }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(panel.name) preview")
                        .accessibilityValue(preview.message ?? "Current board content")
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
    }

    @ViewBuilder
    private func board(_ preview: PanelPreview, in size: CGSize) -> some View {
        if panel.renderStyle == .ledMatrix {
            MatrixCanvas(raster: MatrixRaster.make(panel: panel, cells: preview.cells,
                                                   richCells: preview.richCells, layers: preview.layers),
                         display: panel.matrixDisplay)
                .accessibilityHidden(true)
        } else if let layout = Self.layout(panel: panel, preview: preview, in: size,
                                          calibrationScale: calibrationScale) {
            BoardCanvas(layout: layout, background: panel.backgroundColor,
                        animated: false, code62: panel.effectiveCode62)
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }

    static func layout(panel: Panel, preview: PanelPreview, in viewport: CGSize,
                       calibrationScale: Double?) -> BoardLayout? {
        guard viewport.width > 1, viewport.height > 1,
              preview.rows > 0, preview.cols > 0 else { return nil }
        return try? BoardLayout.fitting(
            rows: preview.rows, cols: preview.cols, cells: preview.cells,
            in: viewport, mode: calibrationScale == nil ? .fit : .trueScale,
            diagonalInches: panel.screenDiagonalInches,
            calibration: calibrationScale ?? panel.calibrationScale,
            colPitchIn: BoardGeometry.colPitchIn(deviceType: panel.deviceType))
    }
}
