import Foundation

/// Each card's spoken summary of its board, worked out once per panel and
/// picture.
///
/// The browser builds every card up front (`PanelsScreen.grid`), so a
/// remote press or an arriving frame re-runs every card body. For an
/// LED-matrix frame with no server message, the summary is a full
/// `MatrixRaster` pixel build, and the card needs it twice (subtitle and
/// accessibility label). Kept per panel, it is built when the picture
/// changes and read back otherwise.
@MainActor
final class PanelBoardMessageCache {
    private struct Entry {
        let panel: Panel
        let preview: PanelPreview
        let message: String?
    }

    private var entries: [String: Entry] = [:]

    func message(for panel: Panel, preview: PanelPreview, build: () -> String?) -> String? {
        if let entry = entries[panel.id], entry.panel == panel, entry.preview == preview {
            return entry.message
        }
        let message = build()
        entries[panel.id] = Entry(panel: panel, preview: preview, message: message)
        return message
    }

    func removeAll() {
        entries.removeAll()
    }
}
