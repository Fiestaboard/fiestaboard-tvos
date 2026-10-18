import UIKit

/// The app's one place for VoiceOver announcements.
///
/// It exists as a helper because *which* API to call is genuinely unsettled.
/// `AccessibilityNotification.Announcement` lives in the Accessibility
/// framework, not in SwiftUI, and reads as missing to anyone grepping the
/// SwiftUI interfaces — two people audited this and reached opposite
/// conclusions. `UIAccessibility.post` is unambiguously available on tvOS and
/// is what the newer enum wraps, so that is what this calls. If the newer
/// spelling is ever confirmed, it changes here, in one file, rather than at
/// the call sites scattered across the screens.
///
/// Announcements are the only way several of those screens say anything at
/// all; `say(_:recordingIn:)` carries the argument for why.
@MainActor
enum Announce {

    /// Which notification was posted. A plain enum rather than
    /// `UIAccessibility.Notification` so a recorder can name what it heard
    /// without reaching for UIKit.
    enum Kind: Equatable {
        case announcement
        case screenChanged
    }

    /// Where an announcement lands. Injectable for the same reason
    /// `ScreenAwake.sink` is: with the `UIAccessibility.post` call hard-wired
    /// into the call sites, nothing could tell a screen that speaks from one
    /// that has gone silent — every `say` in the app could be deleted and the
    /// suite stayed green, on the output that several screens are the *only*
    /// feedback for.
    typealias Sink = @MainActor (Kind, String?) -> Void

    /// There is one of these per process, so a test that installs a recorder
    /// owns putting the real sink back.
    static var sink: Sink = { kind, message in
        switch kind {
        case .announcement:
            UIAccessibility.post(notification: .announcement, argument: message)
        case .screenChanged:
            UIAccessibility.post(notification: .screenChanged, argument: message)
        }
    }

    /// Speak a message without moving focus. Use for state the user cannot
    /// see because focus is somewhere else — an error, a result, a change
    /// they did not cause.
    static func say(_ message: String) {
        sink(.announcement, message)
    }

    /// Show a message and say it: set the property the screen renders from
    /// and post the announcement, in one step. Every screen that puts a
    /// failure on a model has this shape, so it lives here once.
    ///
    /// Announced from the model rather than from an `.onChange` on that
    /// property in the view, because two identical failures in a row are not
    /// a change: press Sign in twice on an empty form and the same string is
    /// set twice, SwiftUI sees no transition, and VoiceOver stays silent.
    ///
    /// Silence is the whole defect. Everything routed through here renders as
    /// non-focusable `Text` above the controls, so with focus already down on
    /// a field or a button the screen simply stops working, quietly — the
    /// panel list stops having panels on it, a failed save reads as a control
    /// that did nothing, and a refused password says nothing at all, so the
    /// next press goes straight into the board's ten-failures-a-minute
    /// lockout.
    static func say(_ message: String, recordingIn shown: inout String?) {
        shown = message
        say(message)
    }

    /// Tell VoiceOver the screen's contents were replaced. Pass nil to let
    /// the system pick the first element to speak; pass a string to say that
    /// instead and leave focus where the system puts it.
    static func screenChanged(_ message: String? = nil) {
        sink(.screenChanged, message)
    }

    /// Whether VoiceOver is on. Read it to lengthen a timeout, never to build
    /// a second, quieter version of a screen.
    static var isVoiceOverRunning: Bool { UIAccessibility.isVoiceOverRunning }
}
