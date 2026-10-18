import SwiftUI

public struct RootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        ZStack {
            Fiesta.Colors.background.ignoresSafeArea()
            // `value:` is what scopes this, not where it hangs. The same
            // modifier on the ZStack would cover the same descendants — the
            // panel grid's focus layout and the viewer's 810-tile Canvas are
            // inside `content` either way — and would still fire only on a
            // route change. The unscoped `.animation(_:)` that does sweep up
            // every descendant's state change is a different API and is not
            // in use here. Hanging it on `content` excludes exactly one
            // view: the background colour, which must not fade with the
            // screens in front of it.
            //
            // No fade on the way into `.viewer`. That route mounts a fresh
            // 45×18 BoardCanvas, and an opacity transition composites the
            // whole layer offscreen while it draws its first frames and
            // flips its flaps. Hazard 5 in docs/HANDOFF.md is that the
            // single-Canvas bet has never been measured on real hardware and
            // its fallback is a CALayer per tile; an unmeasured cost on top
            // of the unmeasured thing is not worth 0.28s of polish, and the
            // flaps flipping in are the entrance anyway. Leaving the viewer
            // still crossfades: the Canvas is a static layer on its way out
            // by then, not one starting up.
            content
                .transition(.opacity)
                .animation(routeChange, value: model.route)
        }
        .preferredColorScheme(.dark)
        .onOpenURL { model.openTopShelfURL($0) }
    }

    /// `nil` when the route being arrived at is the viewer; see `body`.
    private var routeChange: Animation? {
        if case .viewer = model.route { return nil }
        return .easeInOut(duration: 0.28)
    }

    @ViewBuilder
    private var content: some View {
        switch model.route {
        case .connecting:
            ProgressView().tint(Fiesta.Colors.brand)
        case .connect:
            ConnectScreen()
        case .signIn:
            SignInScreen()
        case .panels:
            PanelsScreen()
        case .viewer(let ref):
            ViewerScreen(ref: ref)
        case .settings:
            SettingsScreen()
        case .fiestaBot:
            if let bot = model.fiestaBot { FiestaBotScreen(model: bot) }
        }
    }
}
