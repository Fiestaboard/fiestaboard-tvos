import XCTest
@testable import FiestaBoardTV

@MainActor
final class DeviceSignInModelTests: XCTestCase {
    func testSlowDownPermanentlyRaisesPollingIntervalAndPauseStopsRequests() async throws {
        let harness = try await DeviceModelHarness()
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.challenge), for: "/auth/device/authorize")
        StubURLProtocol.enqueue(.json(#"{"error":"slow_down"}"#, status: 400), for: "/auth/device/token")
        let sleeper = PollSleeper()
        let model = harness.model(sleep: { seconds in try await sleeper.sleep(seconds) })
        model.start()
        await settle { await sleeper.count == 1 }
        let first = await sleeper.intervals
        XCTAssertEqual(first, [5])
        await sleeper.resume()
        await settle { await sleeper.count == 2 }
        let second = await sleeper.intervals
        XCTAssertEqual(second, [5, 10])
        model.pause()
        await sleeper.resume()
        await Task.yield()
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.url.path.hasSuffix("/token") }.count, 1)
        model.cancel()
    }
    func testCancelDiscardsSecretsAndInvalidatesAdoptionGeneration() async throws {
        let harness = try await DeviceModelHarness()
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.challenge), for: "/auth/device/authorize")
        let sleeper = PollSleeper()
        let model = harness.model(sleep: { seconds in try await sleeper.sleep(seconds) })
        let generation = harness.store.connectionGeneration
        model.start()
        await settle { model.challenge != nil }
        XCTAssertEqual(model.manualURL?.path, "/activate")
        model.cancel()
        XCTAssertNil(model.challenge)
        XCTAssertNil(model.completeURL)
        XCTAssertNotEqual(harness.store.connectionGeneration, generation)
        await sleeper.resume()
    }
    func testResumeAfterExpiryDoesNotPollOldCode() async throws {
        let harness = try await DeviceModelHarness()
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.challenge), for: "/auth/device/authorize")
        let sleeper = PollSleeper()
        var now = Date(timeIntervalSince1970: 1_000)
        let model = harness.model(now: { now }, sleep: { seconds in try await sleeper.sleep(seconds) })
        model.start()
        await settle { model.challenge != nil }
        model.pause()
        now = now.addingTimeInterval(601)
        model.resume()
        XCTAssertEqual(model.state, .failed("This code expired. Choose New code."))
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url.path.hasSuffix("/token") })
        model.cancel()
        await sleeper.resume()
    }
    private func settle(_ condition: () async -> Bool) async {
        for _ in 0..<2_000 { if await condition() { return }; await Task.yield() }
        XCTFail("state machine did not reach expected state")
    }
}

@MainActor
private final class DeviceModelHarness {
    let store: ConnectionStore
    init() async throws {
        StubURLProtocol.reset()
        store = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, credentials: InMemoryCredentialStore(), clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled), for: "/auth/status")
        _ = try await store.connect(to: URL(string: "http://board.test")!, displayName: "Board")
    }
    func model(now: @escaping () -> Date = Date.init, sleep: @escaping (TimeInterval) async throws -> Void) -> DeviceSignInModel {
        DeviceSignInModel(connection: store, now: now, sleep: sleep, onSuccess: {})
    }
}
private actor PollSleeper {
    var intervals: [TimeInterval] = []
    var count: Int { intervals.count }
    private var continuation: CheckedContinuation<Void, Never>?
    func sleep(_ seconds: TimeInterval) async throws {
        intervals.append(seconds)
        await withCheckedContinuation { continuation = $0 }
        try Task.checkCancellation()
    }
    func resume() { continuation?.resume(); continuation = nil }
}
