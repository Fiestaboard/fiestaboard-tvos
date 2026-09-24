import Foundation

/// What this particular Apple TV does with a panel's nightly dim window.
///
/// The window itself lives on the server, on the panel, and every viewer of
/// that panel reads it — the web one included. So the TV's say in it is a
/// device preference, not an edit: overriding it here fixes the room the TV
/// is in without reaching into anyone else's screen.
public enum AutoDimOverride: String, Sendable, CaseIterable {
    /// Dim when the panel says to. Same behaviour as the web viewer.
    case followPanel
    /// Never dim on this TV, whatever the panel says.
    case neverDim
}

/// How far the board has been nudged from centre, in points.
public struct BoardOffset: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = BoardOffset(x: 0, y: 0)
}

/// Burn-in protection: a drift so slow it reads as a still image.
///
/// A TV cannot be told to stop protecting its own panel. Every modern set,
/// and every OLED without exception, watches for content that does not
/// change and progressively pulls brightness down on it; some also shift the
/// image themselves. None of that is reachable from an app. What *is*
/// reachable is the other side of the trigger: content that moves is not
/// static content. A split-flap board between flips is as still as an image
/// gets, so this walks it around a closed path a few points wide.
///
/// Pure, and a function of the clock alone, so two TVs showing the same
/// board stay in step and a test can ask where the board will be.
public enum BoardDrift {

    /// Points of travel either side of centre, per axis.
    public static let defaultAmplitude: Double = 8

    /// One lap of the path. Twenty minutes puts the board's speed at well
    /// under a point per ten seconds — below the threshold at which the eye
    /// reads movement at all, let alone at ten feet.
    public static let defaultPeriod: TimeInterval = 20 * 60

    /// Where the board sits at `date`.
    ///
    /// A figure of eight rather than a circle: the horizontal axis completes
    /// one lap while the vertical completes two, so a given flap's centre
    /// traces a spread of positions instead of retracing one ring.
    public static func offset(at date: Date,
                              amplitude: Double = defaultAmplitude,
                              period: TimeInterval = defaultPeriod) -> BoardOffset {
        guard amplitude > 0, period > 0 else { return .zero }
        let seconds = date.timeIntervalSinceReferenceDate
        var phase = seconds.truncatingRemainder(dividingBy: period) / period
        if phase < 0 { phase += 1 }
        return BoardOffset(x: sin(2 * .pi * phase) * amplitude,
                           y: sin(4 * .pi * phase) * amplitude)
    }
}

/// Device-side preferences for a TV that is left showing a board.
///
/// Deliberately per-device and deliberately not sent anywhere. The panel's
/// own configuration is the board's; these are the room's.
public final class SignageSettings: @unchecked Sendable {

    public static let shared = SignageSettings()

    private enum Key {
        static let autoDimOverride = "fiestaboard.signage.autoDimOverride"
        static let drift = "fiestaboard.signage.driftEnabled"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// What this TV does with the panel's nightly dim window.
    public var autoDimOverride: AutoDimOverride {
        get {
            defaults.string(forKey: Key.autoDimOverride)
                .flatMap(AutoDimOverride.init(rawValue:)) ?? .followPanel
        }
        set { defaults.set(newValue.rawValue, forKey: Key.autoDimOverride) }
    }

    /// Whether the board drifts to keep the TV's panel protection off its
    /// back. Off unless asked for: it moves the picture, and a board that is
    /// only up for a few minutes at a time has nothing to protect.
    public var driftEnabled: Bool {
        get { defaults.bool(forKey: Key.drift) }
        set { defaults.set(newValue, forKey: Key.drift) }
    }

    /// Where the board should sit right now, given the above.
    public func drift(at date: Date) -> BoardOffset {
        driftEnabled ? BoardDrift.offset(at: date) : .zero
    }
}
