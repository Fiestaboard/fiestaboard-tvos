import SwiftUI

public struct RootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        ZStack {
            Fiesta.Colors.background.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .onOpenURL { model.openTopShelfURL($0) }
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
        }
    }
}
