import XCTest
@testable import FiestaBoardTV

/// A3 — "Approved by {username}" after device-code sign-in (PHASE-4-TV-PLAN
/// A3, fact 12, DD6). One `GET /auth/status` with the new bearer; no toast
/// for a null username or after a password sign-in. No 07b frame for the
/// toast itself (DD6; the 07b designer owes it, as on Android G3).
@MainActor
final class ApprovedByTests: XCTestCase {

    /// `Tests/Fixtures/tv-auth-status-v1.json`, byte-identical to Android's.
    private func fixtureCase(_ name: String) throws -> String {
        let url = TVSnapshot.repoRoot.appendingPathComponent("Tests/Fixtures/tv-auth-status-v1.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let value = try XCTUnwrap(root[name], name)
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    func testTheFixtureDecodes() throws {
        let tv = try JSONDecoder().decode(AuthStatus.self, from: Data(try fixtureCase("tv").utf8))
        XCTAssertEqual(tv.username, "maya")
        XCTAssertEqual(tv.authKind, "tv")
        let none = try JSONDecoder().decode(AuthStatus.self, from: Data(try fixtureCase("tv_no_username").utf8))
        XCTAssertNil(none.username)
        XCTAssertNil(none.authKind)
    }

    func testTheToastCopy() {
        XCTAssertEqual(TVCopy.DeviceSignIn.approvedBy("maya"), "Approved by maya")
    }

    private func approve(statusCase: String) async throws -> (approver: String??, statusRequests: Int) {
        StubURLProtocol.reset()
        let store = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                    credentials: InMemoryCredentialStore(),
                                    clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled), for: "/auth/status")
        _ = try await store.connect(to: URL(string: "http://board.test")!, displayName: "Board")
        let before = StubURLProtocol.requests.filter { $0.url.path.hasSuffix("/auth/status") }.count
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.challenge), for: "/auth/device/authorize")
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.token), for: "/auth/device/token")
        StubURLProtocol.enqueue(.json(try fixtureCase(statusCase)), for: "/auth/status")
        var approver: String?? = .none
        let model = DeviceSignInModel(connection: store, deviceName: .fallback,
                                      sleep: { _ in }, onSuccess: { approver = .some($0) })
        model.start()
        for _ in 0..<300 where approver == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        let after = StubURLProtocol.requests.filter { $0.url.path.hasSuffix("/auth/status") }
        return (approver, after.count - before)
    }

    func testApprovalReadsTheApproverOnceWithTheNewBearer() async throws {
        let result = try await approve(statusCase: "tv")
        XCTAssertEqual(result.approver, .some("maya"))
        XCTAssertEqual(result.statusRequests, 1, "one /auth/status after approval")
        XCTAssertEqual(StubURLProtocol.requests.last { $0.url.path.hasSuffix("/auth/status") }?.authorization,
                       "Bearer fb_tv_test-only")
    }

    func testANullUsernameShowsNoToast() async throws {
        let result = try await approve(statusCase: "tv_no_username")
        XCTAssertEqual(result.approver, .some(nil))
    }

    func testTheAppShowsTheNoticeThenClearsIt() async throws {
        let app = AppModel(connection: ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                                       credentials: InMemoryCredentialStore()),
                           deviceName: .fallback)
        app.showNotice(TVCopy.DeviceSignIn.approvedBy("maya"), for: .milliseconds(50))
        XCTAssertEqual(app.notice, "Approved by maya")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(app.notice)
        app.finishSignIn(approvedBy: nil)
        XCTAssertNil(app.notice, "no toast without a username")
    }
}
