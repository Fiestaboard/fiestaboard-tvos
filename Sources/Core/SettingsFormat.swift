import Foundation

/// DD21: LED spacing in its shortest exact form, and the presets both TV apps
/// offer (Android TV `LedSpacing`). `Int(pitch)` used to read 2.5 as "2 mm".
public enum LEDSpacing {
    public static let presets: [Double] = [1, 2, 2.5, 3, 4, 5, 6, 8, 10, 12, 16, 20]

    /// "6", "2.5": whole numbers without a decimal, fractions with one.
    public static func number(_ millimeters: Double) -> String {
        let tenths = (millimeters * 10).rounded() / 10
        return tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", tenths)
    }

    /// "6 mm", "2.5 mm".
    public static func label(_ millimeters: Double) -> String { "\(number(millimeters)) mm" }
}

/// 12-hour clock times for the TV ("10:00 PM"), the CANON across the TV apps.
public enum Clock12 {
    /// `minutes` after midnight.
    public static func label(minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        let hour = m / 60, minute = m % 60
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h12, minute, hour < 12 ? "AM" : "PM")
    }

    /// "HH:MM" (24-hour, the hub's form) → "10:00 PM"; the input when it doesn't parse.
    public static func label(hhmm: String) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return hhmm }
        return label(minutes: parts[0] * 60 + parts[1])
    }
}

/// A8b (`248:110205`): what each OLED care row says, and whether care is on
/// at all (DD17: the Settings row reads "On", or "Off" only when everything
/// is off; the same rule as Android TV's `OledCare.isOn`).
public struct OLEDCareSummary: Equatable, Sendable {
    public let brightness: String
    public let movement: String
    public let night: String
    public let rest: String
    public let breaks: String
    public let rotation: String
    public let disconnected: String
    public let screensaver: String
    public let isOn: Bool

    /// `neverDim`: this TV's "Never dim" override of the panel's schedule.
    public init(_ c: OLEDCareConfiguration, neverDim: Bool) {
        brightness = "\(c.brightness) %"
        movement = !c.movement ? "Off" : (c.movementRange > 8 ? "Wider" : "Gentle")
        switch c.nightMode {
        case .followPanel: night = "Follow panel schedule"
        case .never: night = "Never dim"
        case .custom: night = "Custom"
        }
        rest = c.restEnabled ? "\(Clock12.label(minutes: c.restStart)) – \(Clock12.label(minutes: c.restEnd))" : "Off"
        breaks = c.breaksEnabled ? "Every \(c.breakInterval) min" : "Off"
        rotation = c.rotationEnabled ? "On" : "Off"
        switch c.disconnected {
        case .keep: disconnected = "Keep last frame"
        case .dim: disconnected = "Dim after \(c.disconnectDelay) min"
        case .rest: disconnected = "Rest after \(c.disconnectDelay) min"
        }
        screensaver = c.allowScreensaver ? "On" : "Off"
        isOn = c.brightness < 100 || c.movement || (c.nightMode != .never && !neverDim)
            || c.restEnabled || c.breaksEnabled || c.rotationEnabled || c.disconnected != .keep
    }

    /// The This Apple TV row (A8 `166:206997`).
    public var rowValue: String { isOn ? "On · only this Apple TV" : "Off" }
}
