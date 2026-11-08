import XCTest
@testable import FiestaBoardTV

/// A3 — the device name (PHASE-4-TV-PLAN §2.2 A3, fact 10, DD3).
///
/// Without the user-assigned-device-name entitlement (O6, owner-pending),
/// `UIDevice.current.name` is the model name, "Apple TV". A name is
/// user-assigned only when it differs from the model; otherwise the app
/// sends "Apple TV" and says so honestly (DD3, `249:110254`).
final class DeviceNameTests: XCTestCase {

    // MARK: Choosing

    func testANameThatIsNotTheModelIsUserAssigned() {
        XCTAssertEqual(DeviceName.choose(system: "Living Room", model: "Apple TV"), .assigned("Living Room"))
    }

    func testTheModelNameIsTheFallback() {
        XCTAssertEqual(DeviceName.choose(system: "Apple TV", model: "Apple TV"), .fallback)
        XCTAssertEqual(DeviceName.choose(system: "apple tv", model: "Apple TV"), .fallback, "case-insensitive")
        XCTAssertEqual(DeviceName.choose(system: "", model: "Apple TV"), .fallback)
        XCTAssertEqual(DeviceName.choose(system: nil, model: "Apple TV"), .fallback)
        XCTAssertEqual(DeviceName.choose(system: " \n\t", model: "Apple TV"), .fallback)
    }

    func testWhatIsSent() {
        XCTAssertEqual(DeviceNameChoice.assigned("Living Room").sent, "Living Room")
        XCTAssertEqual(DeviceNameChoice.fallback.sent, "Apple TV")
    }

    // MARK: Sanitising (hub accepts 1–100 characters, no control characters)

    func testControlCharactersAndWhitespaceCollapse() {
        XCTAssertEqual(DeviceName.sanitize("  Living\u{0}Room\n\tTV  "), "Living Room TV")
        XCTAssertEqual(DeviceName.sanitize("Kids\u{7}’ room"), "Kids ’ room")
    }

    func testTheNameIsCappedAtOneHundredCharacters() {
        let long = String(repeating: "é", count: 140)
        XCTAssertEqual(DeviceName.sanitize(long).count, 100)
    }

    func testAnEmptyResultFallsBack() {
        XCTAssertEqual(DeviceName.choose(system: "\u{0}\u{1}", model: "Apple TV"), .fallback)
    }

    /// The old `prefix(80)` cut names the hub would accept.
    func testTheWireCapIsTheHubs() async throws {
        StubURLProtocol.reset()
        let client = FiestaClient(baseURL: URL(string: "http://board.test")!, session: StubURLProtocol.makeSession())
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.challenge), for: "/auth/device/authorize")
        let ninety = String(repeating: "n", count: 90)
        _ = try await client.beginDeviceSignIn(deviceName: ninety, appVersion: "1")
        let body = try XCTUnwrap(StubURLProtocol.requests.last?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["device_name"] as? String, ninety)
    }

    // MARK: DD3 copy — A2 166:147647 and fallback 249:110266, verbatim

    func testTheAssignedNameSentenceIsTheA2Frame() {
        XCTAssertEqual(TVCopy.DeviceSignIn.scopeLine(for: .assigned("Living Room")),
                       "This TV will appear as “Living Room”, its Apple TV name. It can show your FiestaPanel displays and adjust how they look on this screen. It can’t change pages, messages or settings.")
    }

    func testTheFallbackSentenceIsTheDD3Frame() {
        XCTAssertEqual(TVCopy.DeviceSignIn.scopeLine(for: .fallback),
                       "This TV will appear as “Apple TV”. It can show your FiestaPanel displays and adjust how they look on this screen. It can’t change pages, messages or settings.")
    }
}

/// The name reaches the hub on every path that creates a TV credential.
@MainActor
final class DeviceNameOnTheWireTests: XCTestCase {
    private let host = URL(string: "http://board.test")!

    private func connectedStore(deviceName: String) async throws -> ConnectionStore {
        StubURLProtocol.reset()
        let store = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                    credentials: InMemoryCredentialStore(),
                                    clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) })
        store.deviceName = deviceName
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled), for: "/auth/status")
        _ = try await store.connect(to: host, displayName: "Board")
        return store
    }

    private func sentName(_ path: String) throws -> String? {
        let request = try XCTUnwrap(StubURLProtocol.requests.last { $0.url.path.hasSuffix(path) }, path)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any])
        return json["device_name"] as? String
    }

    func testPasswordSignInSendsTheDeviceName() async throws {
        let store = try await connectedStore(deviceName: "Living Room")
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.token), for: "/auth/device/login")
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.enabled), for: "/auth/status")
        try await store.signIn(username: "user", password: "password")
        XCTAssertEqual(try sentName("/auth/device/login"), "Living Room")
    }

    func testDeviceCodeSignInSendsTheAppsChoice() async throws {
        let store = try await connectedStore(deviceName: "unused")
        StubURLProtocol.enqueue(.json(DeviceAuthorizationTests.challenge), for: "/auth/device/authorize")
        let model = DeviceSignInModel(connection: store, deviceName: .assigned("Living Room"),
                                      sleep: { _ in try await Task.sleep(for: .seconds(60)) }, onSuccess: { _ in })
        model.start()
        for _ in 0..<300 where model.challenge == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(try sentName("/auth/device/authorize"), "Living Room")
        model.cancel()
    }

    func testTheAppModelHandsTheStoreItsChoice() {
        let store = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                    credentials: InMemoryCredentialStore())
        _ = AppModel(connection: store, deviceName: .assigned("Den"))
        XCTAssertEqual(store.deviceName, "Den")
        let fallback = ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                       credentials: InMemoryCredentialStore())
        _ = AppModel(connection: fallback, deviceName: .fallback)
        XCTAssertEqual(fallback.deviceName, "Apple TV")
    }
}
