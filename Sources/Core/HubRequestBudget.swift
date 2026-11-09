import Foundation

/// How many background requests the TV may have open at a hub at once.
///
/// A7b (#24 review S1): a hub is often a Raspberry Pi. The panel grid's
/// frame fetcher and Top Shelf's status fetcher each bound themselves, but
/// they used to do it separately, so a first load put both batches (four
/// frames and four statuses) on the hub together. Both now take their
/// slots from one budget. Waiters are served first come, first served.
public actor HubRequestBudget {
    public nonisolated let limit: Int
    private var inUse = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    private func acquire() async {
        if inUse < limit {
            inUse += 1
            return
        }
        // The slot is handed over by `release`, so `inUse` stays put.
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            inUse -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// Runs `operation` once a slot is free and gives the slot back after.
    /// A cancelled caller still waits its turn; its request then fails fast.
    public nonisolated func run<T>(_ operation: () async throws -> T) async throws -> T {
        await acquire()
        do {
            let value = try await operation()
            await release()
            return value
        } catch {
            await release()
            throw error
        }
    }
}
