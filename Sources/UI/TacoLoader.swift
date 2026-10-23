import SwiftUI
import UIKit

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
            TacoAnimationView(isAnimating: isAnimating && !reduceMotion && scenePhase == .active)
                .frame(width: size.points, height: size.points)
                .accessibilityHidden(true)
            if let label { Text(label) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label ?? "Loading…"))
        .accessibilityIdentifier("taco-loader")
    }

}

/// Cache image objects once, even when several panel previews are loading.
/// Repeated references preserve GIF frame delays without duplicate pixel data.
struct TacoAnimation {
    let images: [UIImage]
    let timedImages: [UIImage]
    let duration: TimeInterval

    static let shared: TacoAnimation? = {
        struct Manifest: Decodable {
            struct Frame: Decodable {
                let file: String
                let durationMs: Int
            }
            let frames: [Frame]
        }
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "TacoLoader"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              !manifest.frames.isEmpty,
              manifest.frames.allSatisfy({ $0.durationMs > 0 }) else { return nil }
        let images = manifest.frames.compactMap { frame in
            UIImage(contentsOfFile: url.deletingLastPathComponent().appendingPathComponent(frame.file).path)
        }
        guard images.count == manifest.frames.count else { return nil }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let tick = manifest.frames.reduce(manifest.frames[0].durationMs) { gcd($0, $1.durationMs) }
        let timedImages = zip(images, manifest.frames).flatMap { image, frame in
            Array(repeating: image, count: frame.durationMs / tick)
        }
        return TacoAnimation(images: images, timedImages: timedImages,
                             duration: Double(manifest.frames.reduce(0) { $0 + $1.durationMs }) / 1000)
    }()
}

private struct TacoAnimationView: UIViewRepresentable {
    let isAnimating: Bool

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: TacoAnimation.shared?.images.first)
        view.contentMode = .scaleAspectFit
        view.isAccessibilityElement = false
        view.layer.magnificationFilter = .nearest
        view.layer.minificationFilter = .nearest
        view.animationImages = TacoAnimation.shared?.timedImages
        view.animationDuration = TacoAnimation.shared?.duration ?? 0
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if isAnimating {
            if !view.isAnimating { view.startAnimating() }
        } else {
            view.stopAnimating()
        }
    }

    static func dismantleUIView(_ view: UIImageView, coordinator: ()) {
        view.stopAnimating()
        view.animationImages = nil
    }
}
