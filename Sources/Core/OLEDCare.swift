import Foundation

public enum OLEDAnswer: String, CaseIterable { case unanswered, yes, no, unsure, skip }
public enum OLEDNightMode: String, CaseIterable { case followPanel, never, custom }
public enum OLEDDisconnect: String, CaseIterable { case keep, dim, rest }
public enum OLEDPlacement: String, CaseIterable { case center, upperLeft, upperRight, lowerLeft, lowerRight }

/// Device-local controls. Selecting a TV type never applies a preset.
public struct OLEDCareConfiguration: Equatable {
    public var answer: OLEDAnswer = .unanswered
    public var invitationDismissed = false
    public var brightness = 100
    public var movement = false
    public var movementRange = 8
    public var nightMode: OLEDNightMode = .followPanel
    public var nightStart = 1320
    public var nightEnd = 420
    public var nightLevel = 35
    public var restEnabled = false
    public var restStart = 1320
    public var restEnd = 420
    public var breaksEnabled = false
    public var breakInterval = 60
    public var breakDuration = 5
    public var rotationEnabled = false
    public var placements: [OLEDPlacement] = [.center, .upperLeft]
    public var rotationInterval = 5
    public var disconnected: OLEDDisconnect = .keep
    public var disconnectDelay = 5
    public var allowScreensaver = false
    public init() {}
}

/// Read fields independently so an unknown future enum cannot discard valid preferences.
public final class OLEDCareStore {
    public static let key = "fiestaboard.oledCare.v1"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> OLEDCareConfiguration {
        var c = OLEDCareConfiguration()
        let d = defaults.dictionary(forKey: Self.key) ?? [:]
        func number(_ key: String, _ options: [Int], _ fallback: Int) -> Int {
            guard let n = d[key] as? Int, options.contains(n) else { return fallback }; return n
        }
        func minute(_ key: String, _ fallback: Int) -> Int { number(key, Array(0..<1440), fallback) }
        c.answer = (d["answer"] as? String).flatMap(OLEDAnswer.init) ?? .unanswered
        c.invitationDismissed = d["invitationDismissed"] as? Bool ?? false
        c.brightness = number("brightness", [25, 50, 75, 100], 100)
        c.movement = d["movement"] as? Bool ?? defaults.bool(forKey: "fiestaboard.signage.driftEnabled")
        c.movementRange = number("movementRange", [8, 24], 8)
        let legacyNever = defaults.string(forKey: "fiestaboard.signage.autoDimOverride") == "neverDim"
        c.nightMode = (d["nightMode"] as? String).flatMap(OLEDNightMode.init) ?? (legacyNever ? .never : .followPanel)
        c.nightStart = minute("nightStart", 1320); c.nightEnd = minute("nightEnd", 420)
        c.nightLevel = number("nightLevel", [10, 25, 35, 50], 35)
        c.restEnabled = d["restEnabled"] as? Bool ?? false
        c.restStart = minute("restStart", 1320); c.restEnd = minute("restEnd", 420)
        c.breaksEnabled = d["breaksEnabled"] as? Bool ?? false
        c.breakInterval = number("breakInterval", [30, 60, 120], 60)
        c.breakDuration = number("breakDuration", [1, 5, 10], 5)
        c.rotationEnabled = d["rotationEnabled"] as? Bool ?? false
        if let values = d["placements"] as? [String] {
            c.placements = values.compactMap(OLEDPlacement.init).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }
        c.rotationInterval = number("rotationInterval", [1, 5, 15], 5)
        c.disconnected = (d["disconnected"] as? String).flatMap(OLEDDisconnect.init) ?? .keep
        c.disconnectDelay = number("disconnectDelay", [1, 5, 15], 5)
        c.allowScreensaver = d["allowScreensaver"] as? Bool ?? false
        return c
    }
    public func save(_ c: OLEDCareConfiguration) {
        defaults.set([
            "answer": c.answer.rawValue, "invitationDismissed": c.invitationDismissed,
            "brightness": c.brightness, "movement": c.movement, "movementRange": c.movementRange,
            "nightMode": c.nightMode.rawValue, "nightStart": c.nightStart, "nightEnd": c.nightEnd, "nightLevel": c.nightLevel,
            "restEnabled": c.restEnabled, "restStart": c.restStart, "restEnd": c.restEnd,
            "breaksEnabled": c.breaksEnabled, "breakInterval": c.breakInterval, "breakDuration": c.breakDuration,
            "rotationEnabled": c.rotationEnabled, "placements": c.placements.map(\.rawValue), "rotationInterval": c.rotationInterval,
            "disconnected": c.disconnected.rawValue, "disconnectDelay": c.disconnectDelay, "allowScreensaver": c.allowScreensaver
        ], forKey: Self.key)
        defaults.set(c.movement, forKey: "fiestaboard.signage.driftEnabled")
        defaults.set(c.nightMode == .never ? "neverDim" : "followPanel", forKey: "fiestaboard.signage.autoDimOverride")
    }
}

public struct OLEDCareOutput: Equatable {
    public var brightness: Double = 1
    public var resting = false
    public var keepAwake = true
    public var placement: OLEDPlacement = .center
    public var rotating = false
    public var outageDimmed = false
}

public enum OLEDCarePolicy {
    public static func inWindow(_ minute: Int, start: Int, end: Int) -> Bool {
        guard start != end else { return false }
        return start < end ? minute >= start && minute < end : minute >= start || minute < end
    }
    public static func evaluate(_ c: OLEDCareConfiguration, minute: Int, panelDimmed: Bool = false,
                                elapsed: Double = 0, unavailable: Double = 0, breakRest: Bool = false,
                                wakeOverride: Bool = false, foreground: Bool = true, viewing: Bool = true) -> OLEDCareOutput {
        let night = c.nightMode == .followPanel ? panelDimmed : c.nightMode == .custom && inWindow(minute, start: c.nightStart, end: c.nightEnd)
        let outage = unavailable >= Double(c.disconnectDelay * 60)
        let rest = !wakeOverride && ((c.restEnabled && inWindow(minute, start: c.restStart, end: c.restEnd)) || (outage && c.disconnected == .rest) || breakRest)
        let dim = night || (!wakeOverride && outage && c.disconnected == .dim)
        let rotating = c.rotationEnabled && c.placements.count >= 2
        let index = Int(max(0, elapsed) / Double(max(1, c.rotationInterval) * 60))
        return OLEDCareOutput(brightness: rest ? 0 : Double(c.brightness) / 100 * (dim ? Double(c.nightLevel) / 100 : 1),
                              resting: rest, keepAwake: foreground && viewing && !rest && !c.allowScreensaver,
                              placement: rotating ? c.placements[index % c.placements.count] : .center, rotating: rotating,
                              outageDimmed: !wakeOverride && outage && c.disconnected == .dim)
    }
}

/// App-owned monotonic session; data polls only update availability, never restart deadlines.
public struct OLEDCareSession {
    private var lastTime: Double?
    private var wasViewing = false
    private var elapsed = 0.0
    private var breakElapsed = 0.0
    private var unavailableElapsed = 0.0
    private var wasUnavailable = false
    private var wakeUntil = 0.0
    private var output = OLEDCareOutput()
    public init() {}
    public mutating func update(_ c: OLEDCareConfiguration, now: Double, minute: Int,
                                foreground: Bool, viewing: Bool, unavailable: Bool, panelDimmed: Bool = false) -> OLEDCareOutput {
        let active = foreground && viewing
        let delta = active && wasViewing ? max(0, now - (lastTime ?? now)) : 0
        elapsed += delta
        if c.breaksEnabled { breakElapsed += delta } else { breakElapsed = 0 }
        if unavailable { unavailableElapsed += wasUnavailable ? delta : 0 } else { unavailableElapsed = 0 }
        let interval = Double(c.breakInterval * 60), duration = Double(c.breakDuration * 60)
        // Pause partial intervals; cancel an active break so returning is visible.
        if !active && breakElapsed >= interval { breakElapsed = 0 }
        if breakElapsed >= interval + duration { breakElapsed = 0 }
        lastTime = now; wasViewing = active; wasUnavailable = unavailable
        output = OLEDCarePolicy.evaluate(c, minute: minute, panelDimmed: panelDimmed, elapsed: elapsed,
            unavailable: unavailable ? unavailableElapsed : 0, breakRest: c.breaksEnabled && breakElapsed >= interval,
            wakeOverride: now < wakeUntil, foreground: foreground, viewing: viewing)
        return output
    }
    /// Returns whether this press was consumed waking rest, so it cannot activate a hidden control.
    @discardableResult public mutating func interact(now: Double) -> Bool {
        let consumed = output.resting
        if consumed || output.outageDimmed { wakeUntil = now + 300 }
        if consumed { breakElapsed = 0 }
        return consumed
    }
}

/// A viewport with enough black surround for every point of the movement path.
public struct OLEDCareGeometry {
    public let width: Double
    public let height: Double
    public let x: Double
    public let y: Double
    public init(width: Double, height: Double, config: OLEDCareConfiguration, rotating: Bool,
                placement: OLEDPlacement, elapsed: Double, reduceMotion: Bool) {
        let inset = config.movement ? min(Double(config.movementRange), min(width, height) / 2) : 0
        let availableWidth = max(1, width - 2 * inset), availableHeight = max(1, height - 2 * inset)
        self.width = availableWidth * (rotating ? 0.8 : 1)
        self.height = availableHeight * (rotating ? 0.8 : 1)
        let phase = elapsed / 1200 * 2 * Double.pi
        let dx = config.movement && !reduceMotion ? sin(phase) * inset : 0
        let dy = config.movement && !reduceMotion ? sin(phase * 2) * inset : 0
        let left = placement == .upperLeft || placement == .lowerLeft
        let right = placement == .upperRight || placement == .lowerRight
        let upper = placement == .upperLeft || placement == .upperRight
        let lower = placement == .lowerLeft || placement == .lowerRight
        x = width / 2 + (left ? -1 : right ? 1 : 0) * (availableWidth - self.width) / 2 + dx
        y = height / 2 + (upper ? -1 : lower ? 1 : 0) * (availableHeight - self.height) / 2 + dy
    }
}
