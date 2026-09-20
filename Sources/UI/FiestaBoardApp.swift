import SwiftUI

@main
struct FiestaBoardApp: App {
    @State private var model = AppModel(connection: ConnectionStore(),
                                        topShelfStore: TopShelfSnapshotStore.shared())

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
