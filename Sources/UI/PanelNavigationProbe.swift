#if DEBUG
import UIKit

/// Opt-in timing evidence, containing no board names, messages or addresses.
/// Display-link gaps measure main-run-loop delays, not GPU frame delivery.
@MainActor
final class PanelNavigationProbe: NSObject {
    static let shared = PanelNavigationProbe()
    private let enabled = UserDefaults.standard.bool(forKey: "fiestaboard.panelProfile")
    private let writer = DispatchQueue(label: "FiestaBoard.panelMetrics", qos: .utility)
    private var link: CADisplayLink?
    private var previous: Double?
    private var samples: [[String: Any]] = []
    private var frames = 0
    private let recordingID = UUID().uuidString
    static let blankPreviews = UserDefaults.standard.bool(forKey: "fiestaboard.panelProfileBlank")

    func start() {
        guard enabled, link == nil else { return }
        event("browser.appear")
        event(Self.blankPreviews ? "control.blankPreviews" : "control.realPreviews")
        NotificationCenter.default.addObserver(self, selector: #selector(focusUpdated(_:)),
            name: UIFocusSystem.didUpdateNotification, object: nil)
        previous = nil
        let displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    func stop() {
        guard enabled else { return }
        event("browser.disappear")
        link?.invalidate()
        link = nil
        NotificationCenter.default.removeObserver(self, name: UIFocusSystem.didUpdateNotification, object: nil)
        previous = nil
        flush()
    }

    func event(_ name: String, began: Double? = nil, index: Int? = nil) {
        guard enabled else { return }
        let now = CACurrentMediaTime()
        var sample: [String: Any] = ["event": name, "time": now]
        if let began { sample["duration_ms"] = (now - began) * 1000 }
        if let index { sample["index"] = index }
        if samples.count >= 12_000 { samples.removeFirst(6_000) }
        samples.append(sample)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if let previous { event("displayLink", began: previous) }
        previous = now
        frames += 1
        if frames % 120 == 0 { flush() }
    }

    @objc private func focusUpdated(_ notification: Notification) {
        event("focus.native")
    }

    private func flush() {
        let captured = samples
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PanelNavigation", isDirectory: true)
        let url = directory.appendingPathComponent("\(recordingID).json")
        writer.async {
            if let data = try? JSONSerialization.data(withJSONObject: captured) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
#endif
