import SwiftUI

/// A shared, lightweight indeterminate loading indicator. The artwork is
/// decorative; VoiceOver gets one stable status instead of animation updates.
struct TacoLoader: View {
    enum Size {
        case small, regular, large

        var points: CGFloat {
            switch self {
            case .small: return 36
            case .regular: return 80
            case .large: return 128
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let label: LocalizedStringKey?
    private let size: Size
    private let isAnimating: Bool

    init(_ label: LocalizedStringKey? = nil, size: Size = .regular, isAnimating: Bool = true) {
        self.label = label
        self.size = size
        self.isAnimating = isAnimating
    }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if isAnimating && !reduceMotion && scenePhase == .active {
                    taco.keyframeAnimator(initialValue: Hop(), repeating: true) { content, hop in
                        content
                            .scaleEffect(x: hop.scaleX, y: hop.scaleY, anchor: .bottom)
                            .offset(y: hop.height * size.points)
                    } keyframes: { _ in
                        // A small hop, soft landing, then a rest: 1.92 seconds.
                        KeyframeTrack(\.height) {
                            LinearKeyframe(0, duration: 0.14)
                            CubicKeyframe(-0.14, duration: 0.22)
                            CubicKeyframe(0, duration: 0.26)
                            LinearKeyframe(0, duration: 1.30)
                        }
                        KeyframeTrack(\.scaleX) {
                            CubicKeyframe(1.06, duration: 0.14)
                            CubicKeyframe(0.97, duration: 0.22)
                            CubicKeyframe(1, duration: 0.26)
                            CubicKeyframe(1.06, duration: 0.10)
                            CubicKeyframe(1, duration: 0.14)
                            LinearKeyframe(1, duration: 1.06)
                        }
                        KeyframeTrack(\.scaleY) {
                            CubicKeyframe(0.94, duration: 0.14)
                            CubicKeyframe(1.03, duration: 0.22)
                            CubicKeyframe(1, duration: 0.26)
                            CubicKeyframe(0.94, duration: 0.10)
                            CubicKeyframe(1, duration: 0.14)
                            LinearKeyframe(1, duration: 1.06)
                        }
                    }
                } else {
                    taco
                }
            }
            .frame(width: size.points, height: size.points)
            .accessibilityHidden(true)
            if let label { Text(label) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label ?? "Loading…"))
        .accessibilityIdentifier("taco-loader")
    }

    private var taco: some View {
        Image("TacoLoader")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size.points * 0.82, height: size.points * 0.82)
            .offset(y: size.points * 0.07)
    }

    private struct Hop {
        var height: CGFloat = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
    }
}
