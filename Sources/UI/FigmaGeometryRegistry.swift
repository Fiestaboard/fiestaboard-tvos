#if DEBUG
import CoreGraphics
import Foundation

/// Where every `figmaNode(_:label:)` view was laid out, keyed by Figma id —
/// the geometry probe's source for Figma parity (PHASE-4-TV-PLAN §2.1, M8).
///
/// DEBUG only. A Release archive must contain none of this; CI's Release
/// archive job checks that with `scripts/check-release-probes.sh`.
///
/// Frames are in global (window) points. The unit-test host reads them in
/// process; UI tests pass `-fiestaboard.figmaProbeOut <path>` and the app
/// writes the registry there as JSON whenever it changes, so the runner can
/// cross-check each frame against `XCUIElement.frame`.
final class FigmaGeometryRegistry: @unchecked Sendable {
    struct Entry: Codable, Equatable {
        let id: String
        var label: String?
        var frame: CGRect
    }

    struct Export: Codable, Equatable {
        var nodes: [Entry]
    }

    static let shared = FigmaGeometryRegistry(
        exportURL: UserDefaults.standard.string(forKey: "fiestaboard.figmaProbeOut")
            .map { URL(fileURLWithPath: $0) })

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let exportURL: URL?
    private var exportScheduled = false

    init(exportURL: URL? = nil) {
        self.exportURL = exportURL
    }

    func record(_ id: String, label: String?, frame: CGRect) {
        lock.lock()
        entries[id] = Entry(id: id, label: label, frame: frame)
        let schedule = exportURL != nil && !exportScheduled
        if schedule { exportScheduled = true }
        lock.unlock()
        if schedule {
            // Coalesce a layout pass's worth of records into one write.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.writeExport() }
        }
    }

    func snapshot() -> [String: Entry] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        entries = [:]
    }

    func exportData() throws -> Data {
        let nodes = snapshot().values.sorted { $0.id < $1.id }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Export(nodes: nodes))
    }

    private func writeExport() {
        lock.lock(); exportScheduled = false; lock.unlock()
        guard let exportURL, let data = try? exportData() else { return }
        try? data.write(to: exportURL, options: .atomic)
    }
}
#endif
