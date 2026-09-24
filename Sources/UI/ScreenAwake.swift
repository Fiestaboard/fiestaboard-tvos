import Foundation
import UIKit

/// The app's single owner of `UIApplication.isIdleTimerDisabled`.
///
/// It used to be owned by `ViewerScreen`, set in `onAppear` and cleared in
/// `onDisappear`. That is the right API and the wrong place: SwiftUI does
/// not promise an order between the outgoing view's `onDisappear` and the
/// incoming view's `onAppear`, and a screen on a wall for a month cannot
/// depend on winning that race every time someone opens Settings.
///
/// So one owner, told what it wants by the route, and asked again whenever
/// the app comes back to the foreground — the same shape the web viewer
/// uses, which re-acquires its wake lock on `visibilitychange`.
@MainActor
final class ScreenAwake {

    /// Where a request lands. Injectable so a test can watch what was asked
    /// for without putting the test host's real display into signage mode.
    typealias Sink = @MainActor (Bool) -> Void

    var sink: Sink

    /// Asked when the app returns to the foreground, so the owner can
    /// restate what it wanted rather than trusting the flag to have survived.
    var onForeground: (@MainActor () -> Void)?

    private(set) var isHeld = false
    private var observer: NSObjectProtocol?
    private let center: NotificationCenter

    init(sink: Sink? = nil, center: NotificationCenter = .default) {
        self.sink = sink ?? { held in UIApplication.shared.isIdleTimerDisabled = held }
        self.center = center
        observer = center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                      object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onForeground?() }
        }
    }

    deinit {
        if let observer { center.removeObserver(observer) }
    }

    /// Restate the request. Always sent through, never short-circuited on
    /// "it is already true": the point of this call is to overwrite whatever
    /// the system or a stray view left behind.
    func hold(_ held: Bool) {
        isHeld = held
        sink(held)
    }
}
