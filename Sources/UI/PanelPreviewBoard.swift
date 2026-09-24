import SwiftUI

/// A panel's board, drawn small enough to sit on a card.
///
/// The same `BoardCanvas` the viewer uses, laid out with the same
/// `BoardLayout.fitting(… mode: .fit …)` — a card should show the board,
/// not a second rendering of it that drifts from the real one. Animation is
/// off: a grid of flipping boards is a grid of running timelines, and the
/// card is a picture, not a display.
struct PanelPreviewBoard: View {
    let panel: Panel
    let preview: PanelPreview

    var body: some View {
        GeometryReader { proxy in
            board(in: proxy.size)
                // One sizing frame around a view that is already a fixed
                // size: `BoardCanvas` carries its own `.frame(width:height:)`
                // and paints its background onto it, so a second flexible
                // frame here would only be noise.
                //
                // This does NOT by itself decide where the board lands.
                // Placement is `PanelCard`'s inset mount — see the note on
                // `PanelCard.boardInset`, and the test that measures it.
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func board(in size: CGSize) -> some View {
        if let layout = Self.layout(panel: panel, preview: preview, in: size) {
            BoardCanvas(layout: layout,
                        background: panel.backgroundColor,
                        animated: false,
                        code62: panel.effectiveCode62)
        } else {
            Color.clear
        }
    }

    /// Nil when there is nothing to lay out — a zero-sized card during the
    /// first layout pass, or a frame with no grid yet.
    static func layout(panel: Panel, preview: PanelPreview, in size: CGSize) -> BoardLayout? {
        guard size.width > 1, size.height > 1 else { return nil }
        guard preview.rows > 0, preview.cols > 0 else { return nil }
        let pitch = BoardGeometry.colPitchIn(deviceType: panel.deviceType)
        return try? BoardLayout.fitting(rows: preview.rows,
                                        cols: preview.cols,
                                        cells: preview.cells,
                                        in: size,
                                        mode: .fit,
                                        diagonalInches: panel.screenDiagonalInches,
                                        calibration: panel.calibrationScale,
                                        colPitchIn: pitch)
    }
}
