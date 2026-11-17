import SnapshotTesting
import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// The goldens' tolerance (#16/#17 review 4.6; #18 re-review). At
/// `precision: 0.995` the DD12 change — ":4420" dropped from the hub card —
/// passed against the old golden unnoticed. A3 sets `precision: 1.0` and
/// keeps `perceptualPrecision: 0.98` (which absorbs glyph anti-aliasing),
/// and proves both halves: a re-render still matches, a five-glyph copy
/// change does not.
@MainActor
final class SnapshotToleranceTests: XCTestCase {

    private func connect(port: Int) async throws -> UIImage {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.tolerance.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
        let model = ConnectModel(app: app)
        let discovery = NeverEndingDiscovery()
        Task { await model.startScan(using: discovery, patience: .seconds(60)) }
        let hub = DiscoveredBoard(id: "http://192.168.1.20:\(port)", name: "FiestaBoard",
                                  host: URL(string: "http://192.168.1.20:\(port)")!)
        for _ in 0..<300 where model.boards.isEmpty {
            discovery.publish([hub])
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        defer { model.stopScan() }
        return TVSnapshot.image(ConnectScreen(model: model).environment(app)
            .background(Fiesta.Colors.background), settle: 0.3)
    }

    func testTheGoldenToleranceIsExact() {
        XCTAssertEqual(TVSnapshot.precision, 1.0)
        XCTAssertEqual(TVSnapshot.perceptualPrecision, 0.98)
    }

    /// Record → verify: the same screen rendered twice compares equal.
    func testARerenderMatchesAtTheGoldenTolerance() async throws {
        let first = try await connect(port: 4420)
        let second = try await connect(port: 4420)
        XCTAssertNil(TVSnapshot.difference(first, second), "a re-render must match exactly enough to verify")
    }

    /// A copy change as small as DD12's must fail at the golden tolerance,
    /// and is the change the old tolerance let through.
    func testAFiveGlyphHostLineChangeFails() async throws {
        let hidden = try await connect(port: 4420)   // "192.168.1.20"
        let shown = try await connect(port: 4421)    // "192.168.1.20:4421"
        XCTAssertNotNil(TVSnapshot.difference(hidden, shown), "\":4421\" on the hub card must fail the golden")
        XCTAssertNil(TVSnapshot.difference(hidden, shown, precision: 0.995),
                     "documents the gap: the pre-A3 tolerance missed it")
    }
}
