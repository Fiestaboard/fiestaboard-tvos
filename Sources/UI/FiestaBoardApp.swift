import SwiftUI

@main
struct FiestaBoardApp: App {
    @State private var model = AppModel(connection: ConnectionStore(),
                                        topShelfStore: TopShelfSnapshotStore.shared(),
                                        deviceName: SystemDeviceName.current)

    init() {
        // The app always uses a dark background. tvOS's default navigation
        // title remains dim even with preferredColorScheme(.dark).
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor.white]
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // UI-test only: the A0 parity proofs launch into a fixture with
            // no model, network or saved state.
            if let fixture = ParityFixtureView.Kind.fromLaunchArguments() {
                ParityFixtureView(kind: fixture)
            } else {
                root
            }
            #else
            root
            #endif
        }
    }

    private var root: some View {
        RootView()
            .environment(model)
            .onAppear {
                BoardFont.registerIfNeeded()
                model.start()
            }
    }
}
