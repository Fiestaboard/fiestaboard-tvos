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

/// A slow image movement path that varies where board content is drawn.
/// Movement may reduce concentrated OLED wear; it cannot guarantee prevention
/// or override the television's own screen protection.
/// Pure and clock-driven so tests can inspect every part of the path.
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
        static let matrixPresentation = "fiestaboard.matrix.presentation"
        static let matrixTransitionStyle = "fiestaboard.matrix.transitionStyle"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var matrixPresentation: MatrixPresentation {
        get {
            guard let data = defaults.data(forKey: Key.matrixPresentation),
                  let value = try? JSONDecoder().decode(MatrixPresentation.self, from: data) else { return .init() }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: Key.matrixPresentation) }
        }
    }

    /// Hardware-style LED transitions are a preference of this TV.
    public var matrixTransitionStyle: MatrixTransitionStyle {
        get {
            defaults.string(forKey: Key.matrixTransitionStyle)
                .flatMap(MatrixTransitionStyle.init(rawValue:)) ?? .characterWipe
        }
        set { defaults.set(newValue.rawValue, forKey: Key.matrixTransitionStyle) }
    }

    /// What this TV does with the panel's nightly dim window.
    public var autoDimOverride: AutoDimOverride {
        get {
            defaults.string(forKey: Key.autoDimOverride)
                .flatMap(AutoDimOverride.init(rawValue:)) ?? .followPanel
        }
        set { defaults.set(newValue.rawValue, forKey: Key.autoDimOverride) }
    }

    /// Whether this device opted into gentle image movement. Off by default.
    public var driftEnabled: Bool {
        get { defaults.bool(forKey: Key.drift) }
        set { defaults.set(newValue, forKey: Key.drift) }
    }

    /// Where the board should sit right now, given the above.
    public func drift(at date: Date) -> BoardOffset {
        driftEnabled ? BoardDrift.offset(at: date) : .zero
    }
}
