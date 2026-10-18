import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let store = TopShelfSnapshotStore.shared() else { return nil }
        return TopShelfContent.make(store: store)
    }
}
