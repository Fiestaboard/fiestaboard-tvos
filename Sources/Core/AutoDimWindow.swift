import Foundation

/// Evaluates a panel's nightly dimming window.
///
/// Against the TV's own clock, matching the web viewer: the window is what
/// the room is doing, not what the server's timezone thinks.
public enum AutoDimWindow {

    /// Minutes since midnight for "HH:MM", or nil if malformed.
    static func minutes(from text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    public static func isDimmed(_ autoDim: AutoDim,
                                at date: Date,
                                calendar: Calendar = .current) -> Bool {
        guard autoDim.enabled,
              let start = minutes(from: autoDim.start),
              let end = minutes(from: autoDim.end),
              start != end else { return false }

        let components = calendar.dateComponents([.hour, .minute], from: date)
        let now = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        // Start inclusive, end exclusive, wrapping past midnight when the
        // window's end is earlier in the day than its start.
        return start < end ? (now >= start && now < end)
                           : (now >= start || now < end)
    }
}
