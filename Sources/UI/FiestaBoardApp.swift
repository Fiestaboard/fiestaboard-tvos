import SwiftUI

@main
struct FiestaBoardApp: App {
    @State private var model = AppModel(connection: ConnectionStore(),
                                        topShelfStore: TopShelfSnapshotStore.shared())

    init() {
        // The app always uses a dark background. tvOS's default navigation
        // title remains dim even with preferredColorScheme(.dark).
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor.white]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear {
                    BoardFont.registerIfNeeded()
                    model.start()
                }
        }
    }
}
