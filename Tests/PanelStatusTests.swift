import CryptoKit
import XCTest
@testable import FiestaBoardTV

/// A6a (4.6 core): every case of the hub-generated `panel-status-v1.json` and
/// of its tvOS companion decodes through `FiestaClient.panelReading`, picks
/// its chip by the hub's precedence on the hub's clock, and reads DD22's copy.
/// Same table as the Android TV twin (G6a, androidtv #19).
final class PanelStatusTests: XCTestCase {

    private static let fixtures = TVSnapshot.repoRoot.appendingPathComponent("Tests/Fixtures")
    private let zone = TimeZone(identifier: "America/Los_Angeles")!

    private func json(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent(name))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private var hub: [String: Any] { get throws { try json("panel-status-v1.json") } }
    private var companion: [String: Any] { get throws { try json("panel-status-v1.tv.json") } }
    private var hubCases: [[String: Any]] { get throws { try XCTUnwrap(hub["cases"] as? [[String: Any]]) } }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private static func httpDate(_ value: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: value)!
    }

    private static func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func read(body: [String: Any], headers: [String: String]) async throws -> PanelReading {
        StubURLProtocol.reset()
        var all = headers
        all["Content-Type"] = "application/json"
        let data = try JSONSerialization.data(withJSONObject: body)
        StubURLProtocol.enqueue(.init(status: 200, body: data, headers: all), for: "/api/panel/lobby")
        let client = FiestaClient(baseURL: URL(string: "http://hub:4420")!, session: StubURLProtocol.makeSession())
        return try await client.panelReading(ref: "lobby")
    }

    private func read(hubCase name: String) async throws -> PanelReading {
        let c = try XCTUnwrap(hubCases.first { $0["name"] as? String == name }, name)
        return try await read(body: c["body"] as! [String: Any], headers: c["headers"] as! [String: String])
    }

    // MARK: The vendored fixture

    func testVendoredFixturesMatchTheirSource() throws {
        let source = try json("SOURCE.json")
        let entry = try XCTUnwrap(source["panel-status-v1.json"] as? [String: Any])
        XCTAssertEqual(entry["path"] as? String, "tests/fixtures/panels/panel-status-v1.json")
        XCTAssertEqual((entry["commit"] as? String)?.count, 40, "a full commit, so the source is unambiguous")
        for (name, value) in source where !name.hasPrefix("$") {
            let data = try Data(contentsOf: Self.fixtures.appendingPathComponent(name))
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hash, (value as? [String: Any])?["sha256"] as? String, "\(name) is copied byte for byte")
        }
    }

    func testTheCompanionCoversEveryHubCase() throws {
        XCTAssertEqual(try hub["protocol"] as? String, "panel-status-v1")
        let names = try hubCases.compactMap { $0["name"] as? String }
        XCTAssertEqual(names.count, 11, "H2b generates 11 hub cases")
        let chips = try XCTUnwrap(companion["chips"] as? [String: Any])
        XCTAssertEqual(Set(chips.keys), Set(names), "every hub case has an expected chip, and only those")
        let clientNames = try (companion["client_cases"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        XCTAssertEqual(Set(clientNames), ["old-server", "date-header-missing", "date-header-skewed",
                                          "override-expired-by-date-header", "hub-unreachable", "reconnected"])
        XCTAssertTrue(Set(clientNames).isDisjoint(with: names))
    }

    // MARK: Every case reads its chip

    private struct Case {
        let name: String
        let body: [String: Any]
        let headers: [String: String]
        let localNow: Date?
        let connection: HubConnection
        let expect: [String: Any]?
    }

    private func allCases() throws -> [Case] {
        let chips = try XCTUnwrap(companion["chips"] as? [String: Any])
        var out: [Case] = []
        for c in try hubCases {
            let name = c["name"] as! String
            out.append(Case(name: name, body: c["body"] as! [String: Any], headers: c["headers"] as! [String: String],
                            localNow: nil, connection: .reachable, expect: chips[name] as? [String: Any]))
        }
        for c in try companion["client_cases"] as! [[String: Any]] {
            let base = try XCTUnwrap(out.first { $0.name == c["from"] as? String }, "\(c["name"]!) from")
            var body = base.body
            for key in c["remove"] as? [String] ?? [] { body.removeValue(forKey: key) }
            let connection: HubConnection = switch c["connection"] as? String {
            case "unreachable": .unreachable
            case "reconnected": .reconnected
            default: .reachable
            }
            out.append(Case(name: c["name"] as! String, body: body,
                            headers: c["headers"] as? [String: String] ?? base.headers,
                            localNow: (c["local_now"] as? String).map(Self.instant),
                            connection: connection, expect: c["expect_chip"] as? [String: Any]))
        }
        return out
    }

    func testEveryCaseDecodesAndReadsItsChip() async throws {
        let cases = try allCases()
        XCTAssertEqual(cases.count, 17)
        for c in cases {
            let reading = try await read(body: c.body, headers: c.headers)
            XCTAssertEqual(reading.hubDate, c.headers["Date"].map(Self.httpDate), "\(c.name): Date header")
            let localNow = try c.localNow ?? XCTUnwrap(reading.hubDate, "\(c.name) needs local_now or a Date")
            let hubNow = HubClock(hubDate: reading.hubDate, receivedAt: localNow).now(at: localNow)
            let chip = PanelStatusChip.chip(status: reading.panel.status, hubNow: hubNow, connection: c.connection)
            guard let expect = c.expect else { XCTAssertNil(chip, "\(c.name): no chip"); continue }
            let content = try PanelStatusChip.content(XCTUnwrap(chip, "\(c.name): a chip"), timeZone: zone)
            XCTAssertEqual(content.kind.rawValue, expect["kind"] as? String, "\(c.name): kind")
            XCTAssertEqual(content.persistent, expect["persistent"] as? Bool, "\(c.name): persistent")
            XCTAssertEqual(content.badge, expect["badge"] as? String, "\(c.name): badge")
            XCTAssertEqual(content.text, expect["text"] as? String, "\(c.name): text")
        }
    }

    // MARK: Decode

    func testStatusDecodesAsInstants() async throws {
        let overrideReading = try await read(hubCase: "override-with-expiry")
        let override = try XCTUnwrap(overrideReading.panel.status)
        XCTAssertEqual(override.mode, .override)
        XCTAssertTrue(override.overrideActive)
        XCTAssertFalse(override.scheduleEnabled)
        XCTAssertEqual(override.overrideExpiresAt, Self.instant("2026-11-08T05:00:37Z"))
        XCTAssertEqual(override.overrideStartedAt, Self.instant("2026-11-08T02:18:00Z"))
        XCTAssertEqual(override.nextChangeAt, Self.instant("2026-11-08T05:00:37Z"))
        XCTAssertEqual(override.nextChangeReason, "override_ends")
        let silencedReading = try await read(hubCase: "silenced-indicator")
        let silenced = try XCTUnwrap(silencedReading.panel.status)
        XCTAssertTrue(silenced.silenced)
        XCTAssertEqual(silenced.silenceMode, .indicator)
        XCTAssertEqual(silenced.silencedUntil, Self.instant("2026-11-08T15:00:00Z"))
        let scheduleReading = try await read(hubCase: "schedule")
        let schedule = try XCTUnwrap(scheduleReading.panel.status)
        XCTAssertEqual(schedule.mode, .schedule)
        XCTAssertEqual(schedule.nextChangeReason, "schedule")
        let pausedReading = try await read(hubCase: "paused")
        XCTAssertTrue(try XCTUnwrap(pausedReading.panel.status).paused)
    }

    /// An old hub (no key) and a removed display (`status: null`) both read as
    /// "no status", and neither is an error.
    func testOldHubAndRemovedDisplayReadAsNoStatus() async throws {
        let old = try await read(body: ["id": "lobby", "name": "Lobby TV", "board_id": "b1"], headers: [:])
        XCTAssertNil(old.panel.status)
        XCTAssertNil(old.hubDate)
        // The real wire (H2b a53903c2f): the board id stays, `board_missing` says so.
        let removed = try await read(hubCase: "board-missing").panel
        XCTAssertNil(removed.status)
        XCTAssertTrue(removed.boardMissing)
        XCTAssertEqual(removed.boardId, "b1")
        XCTAssertNil(removed.rows)
        let healthy = try await read(hubCase: "manual").panel
        XCTAssertFalse(healthy.boardMissing)
    }

    /// No inference from a null board id: the hub always sends one, so a
    /// panel without one is malformed, exactly as before A6a.
    func testANullBoardIdIsStillMalformed() async {
        do {
            _ = try await read(body: ["id": "lobby", "name": "Lobby TV", "board_id": NSNull()], headers: [:])
            XCTFail("expected a decoding error")
        } catch FiestaError.decoding {
            // expected
        } catch {
            XCTFail("expected .decoding, got \(error)")
        }
    }

    /// A PATCH reply (`PanelUpdateResponse`) carries no `status`: a caller that
    /// adopts the patched panel keeps the status it polled.
    func testAPatchReplyKeepsThePolledStatus() async throws {
        let polled = try await read(hubCase: "override-with-expiry").panel
        StubURLProtocol.reset()
        let patched = #"{"id":"lobby","name":"Lobby TV","board_id":"b1","rows":12,"cols":29,"render_style":"split_flap","animations_enabled":true,"incompatible_references":null}"#
        StubURLProtocol.enqueue(.json(patched), for: "/api/panels/lobby")
        let client = FiestaClient(baseURL: URL(string: "http://hub:4420")!, session: StubURLProtocol.makeSession())
        let result = try await client.updatePanel(id: "lobby", animationsEnabled: true)
        XCTAssertNil(result.panel.status, "PanelUpdateResponse has no status")
        let kept = result.panel.keepingStatus(of: polled)
        XCTAssertEqual(kept.status, polled.status)
        XCTAssertTrue(kept.animationsEnabled, "everything else is the patched panel")
        XCTAssertNil(result.panel.keepingStatus(of: nil).status)
    }

    func testUnknownValuesAndOddInstantsAreTolerated() async throws {
        let body: [String: Any] = ["id": "x", "name": "X", "board_id": "b1", "status": [
            "mode": "ambient", "schedule_enabled": true, "override_active": false,
            "override_expires_at": "not a time", "silenced": true,
            "silenced_until": "2026-11-08T07:00:00-08:00", "silence_mode": "lava", "paused": false,
            "next_change_at": "2026-11-08T05:00:00.250Z", "next_change_reason": "comet", "future_key": 1,
        ] as [String: Any]]
        let reading = try await read(body: body, headers: [:])
        let status = try XCTUnwrap(reading.panel.status)
        XCTAssertEqual(status.mode, .manual, "an unknown mode reads as manual")
        XCTAssertNil(status.overrideExpiresAt, "a bad instant is nil, not an error")
        XCTAssertEqual(status.silencedUntil, Self.instant("2026-11-08T15:00:00Z"), "the same instant in another offset")
        XCTAssertNil(status.silenceMode, "an unknown silence mode is unknown")
        XCTAssertEqual(status.nextChangeAt?.timeIntervalSince1970 ?? 0,
                       Self.instant("2026-11-08T05:00:00Z").timeIntervalSince1970 + 0.25, accuracy: 0.001)
        XCTAssertEqual(status.nextChangeReason, "comet")
        // A status that is not an object at all costs the status, not the panel.
        let broken = try await read(body: ["id": "x", "name": "X", "board_id": "b1", "status": "yes"], headers: [:])
        XCTAssertNil(broken.panel.status)
    }

    func testStatusSurvivesAnEncodeRoundTrip() async throws {
        let panel = try await read(hubCase: "override+silenced").panel
        let again = try JSONDecoder().decode(Panel.self, from: JSONEncoder().encode(panel))
        XCTAssertEqual(again, panel)
        XCTAssertNotNil(again.status)
    }

    // MARK: Chip rules

    private func status(mode: PanelMode = .override, scheduleEnabled: Bool = false, overrideActive: Bool = true,
                        expires: Date? = PanelStatusTests.instant("2026-11-08T05:00:00Z"), silenced: Bool = false,
                        silenceMode: SilenceMode? = nil, paused: Bool = false, nextChange: Date? = nil) -> PanelStatus {
        PanelStatus(mode: mode, scheduleEnabled: scheduleEnabled, overrideActive: overrideActive,
                    overrideExpiresAt: expires, overrideStartedAt: nil, silenced: silenced,
                    silencedUntil: silenced ? Self.instant("2026-11-08T15:00:00Z") : nil, silenceMode: silenceMode,
                    paused: paused, nextChangeAt: nextChange, nextChangeReason: nextChange == nil ? nil : "schedule")
    }

    private let hubNow = PanelStatusTests.instant("2026-11-08T02:18:00Z")

    /// H1 review carry: a primary trigger can show while `override_active`, so
    /// the chip names the mode and never what is on screen.
    func testTheOverrideChipNeverClaimsWhatIsOnScreen() throws {
        for expiry in [Self.instant("2026-11-08T05:00:00Z"), nil] {
            let chip = try XCTUnwrap(PanelStatusChip.chip(status: status(expires: expiry), hubNow: hubNow))
            let text = PanelStatusChip.content(chip, timeZone: zone).text
            XCTAssertFalse(text.localizedCaseInsensitiveContains("showing"), text)
        }
    }

    func testTheCountdownRunsOnTheHubClockAndRoundsUp() throws {
        let clock = HubClock(hubDate: Self.instant("2026-11-08T02:23:00Z"), receivedAt: hubNow)
        XCTAssertEqual(clock.now(at: Self.instant("2026-11-08T02:19:00Z")), Self.instant("2026-11-08T02:24:00Z"))
        XCTAssertEqual(HubClock(hubDate: nil, receivedAt: hubNow).now(at: hubNow), hubNow, "no Date: the local clock")
        XCTAssertEqual(HubClock.local.now(at: hubNow), hubNow)
        func text(at now: String) throws -> String {
            let chip = try XCTUnwrap(PanelStatusChip.chip(status: status(), hubNow: Self.instant(now)))
            return PanelStatusChip.content(chip, timeZone: zone).text
        }
        XCTAssertEqual(try text(at: "2026-11-08T04:59:30Z"), "1m left · Holds until 9:00 PM", "never 0m left")
        XCTAssertEqual(try text(at: "2026-11-08T03:59:01Z"), "1h 1m left · Holds until 9:00 PM")
        XCTAssertEqual(try text(at: "2026-11-08T04:00:00Z"), "1h 0m left · Holds until 9:00 PM")
        // One rule for both TV apps: cut to whole seconds, then round up to minutes.
        XCTAssertEqual(PanelStatusChip.left(60.5), "1m left", "60.5 s is 60 s: 1m, as on Android")
        XCTAssertEqual(PanelStatusChip.left(61), "2m left")
        XCTAssertEqual(PanelStatusChip.left(119.9), "2m left")
        XCTAssertEqual(PanelStatusChip.left(3600.9), "1h 0m left")
        XCTAssertEqual(PanelStatusChip.left(0.4), "1m left", "a running override never reads 0m")
        XCTAssertNil(PanelStatusChip.chip(status: status(), hubNow: Self.instant("2026-11-08T05:00:00Z")),
                     "an override ends at its expiry on the hub's clock")
    }

    func testAnExpiredOverrideFallsThroughToSilenceThenSchedule() throws {
        let after = Self.instant("2026-11-08T05:00:01Z")
        let silenced = PanelStatusChip.chip(status: status(silenced: true, silenceMode: .freeze), hubNow: after)
        XCTAssertEqual(silenced?.kind, .silenced)
        let scheduled = PanelStatusChip.chip(status: status(scheduleEnabled: true), hubNow: after)
        XCTAssertEqual(scheduled?.kind, .schedule)
        XCTAssertNil(PanelStatusChip.chip(status: status(), hubNow: after), "schedule off: nothing drives it but the pinned page")
    }

    func testTheScheduleChipNamesOnlyAFutureChange() throws {
        func text(_ next: Date?) throws -> String {
            let s = status(mode: .schedule, scheduleEnabled: true, overrideActive: false, expires: nil, nextChange: next)
            return PanelStatusChip.content(try XCTUnwrap(PanelStatusChip.chip(status: s, hubNow: hubNow)), timeZone: zone).text
        }
        XCTAssertEqual(try text(Self.instant("2026-11-08T05:00:00Z")), "Schedule · next change 9:00 PM")
        XCTAssertEqual(try text(nil), "Schedule")
        XCTAssertEqual(try text(Self.instant("2026-11-08T02:00:00Z")), "Schedule", "a change already past says nothing")
    }

    func testSilenceWithoutAnEndOrAModeStillReads() throws {
        var s = status(overrideActive: false, expires: nil, silenced: true, silenceMode: nil)
        s.silencedUntil = nil
        let chip = try XCTUnwrap(PanelStatusChip.chip(status: s, hubNow: hubNow))
        XCTAssertEqual(PanelStatusChip.content(chip, timeZone: zone).text, "Silenced")
        XCTAssertFalse(chip.persistent)
    }

    func testUnreachableLeadsEvenWithoutAStatus() {
        XCTAssertEqual(PanelStatusChip.chip(status: nil, hubNow: hubNow, connection: .unreachable)?.kind, .hubUnreachable)
        XCTAssertEqual(PanelStatusChip.chip(status: status(paused: true), hubNow: hubNow, connection: .unreachable)?.kind, .hubUnreachable)
        XCTAssertNil(PanelStatusChip.chip(status: nil, hubNow: hubNow))
    }

    // MARK: The store carries the hub clock

    func testThePanelStorePublishesTheHubClockAndTheChip() async throws {
        let local = Self.instant("2026-11-08T02:18:00Z")
        let override = try XCTUnwrap(hubCases.first { $0["name"] as? String == "override-with-expiry" }?["body"])
        let data = try JSONSerialization.data(withJSONObject: override)
        StubURLProtocol.enqueue(.init(status: 200, body: data, headers: [
            "Content-Type": "application/json", "Date": "Sun, 08 Nov 2026 02:23:00 GMT"]), for: "/api/panel/lobby")
        for _ in 0..<6 { StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame") }
        let store = PanelStore(client: FiestaClient(baseURL: URL(string: "http://hub:4420")!, session: StubURLProtocol.makeSession()),
                               ref: "lobby", frameInterval: 0.02, configInterval: 60, clock: { local })
        var found: PanelSnapshot?
        for await snapshot in store.snapshots() where snapshot.panel != nil && !snapshot.cells.isEmpty { found = snapshot; break }
        store.stop()
        let snapshot = try XCTUnwrap(found)
        XCTAssertEqual(snapshot.hubClock.now(at: local), Self.instant("2026-11-08T02:23:00Z"))
        let chip = try XCTUnwrap(snapshot.statusChip(localNow: local, timeZone: zone))
        XCTAssertEqual(chip.text, "2h 38m left · Holds until 9:00 PM")
        XCTAssertEqual(snapshot.statusChip(localNow: local, reconnected: true, timeZone: zone)?.kind, .reconnected)
        let stale = PanelSnapshot(panel: snapshot.panel, cells: [], rows: 0, cols: 0, connection: .stale,
                                  dimmed: false, deleted: false)
        XCTAssertEqual(stale.statusChip(localNow: local, timeZone: zone)?.kind, .hubUnreachable)
        XCTAssertEqual(PanelSnapshot.empty.hubClock, .local)
    }

    /// Review must-fix: the offset of a whole-second `Date` against a
    /// fractional local clock moves on every config read. Unless it moves by
    /// more than `HubClock.tolerance`, the store keeps the clock it has, so
    /// `ViewerModel.apply`'s `!=` still skips an unchanged snapshot.
    func testTheHubClockDoesNotChurnTheSnapshot() async throws {
        let body = try JSONSerialization.data(withJSONObject: XCTUnwrap(
            hubCases.first { $0["name"] as? String == "override-with-expiry" }?["body"]))
        for date in ["Sun, 08 Nov 2026 02:18:00 GMT", "Sun, 08 Nov 2026 02:18:10 GMT", "Sun, 08 Nov 2026 02:18:20 GMT"] {
            StubURLProtocol.enqueue(.init(status: 200, body: body, headers: ["Content-Type": "application/json", "Date": date]),
                                    for: "/api/panel/lobby")
        }
        // Longer than "/api/panel/lobby", so frames never take a config body.
        for _ in 0..<200 { StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/api/panel/lobby/frame") }
        let base = Self.instant("2026-11-08T02:18:00Z").addingTimeInterval(0.2)
        // The local clock runs 10.3 s per config read while the hub's Date runs 10 s.
        let clock: @Sendable () -> Date = {
            let reads = StubURLProtocol.requests.filter { !$0.url.path.hasSuffix("/frame") }.count
            return base.addingTimeInterval(10.3 * Double(max(reads - 1, 0)))
        }
        let suite = "a6a-hub-clock-\(UUID().uuidString)"
        let signage = SignageSettings(defaults: UserDefaults(suiteName: suite)!)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = PanelStore(client: FiestaClient(baseURL: URL(string: "http://hub:4420")!, session: StubURLProtocol.makeSession()),
                               ref: "lobby", frameInterval: 0.01, configInterval: 0.03, clock: clock, signage: signage)
        var byRead: [Int: PanelSnapshot] = [:]
        let deadline = Date().addingTimeInterval(5)
        for await snapshot in store.snapshots() where snapshot.panel != nil && !snapshot.cells.isEmpty {
            let reads = StubURLProtocol.requests.filter { !$0.url.path.hasSuffix("/frame") }.count
            if byRead[reads] == nil { byRead[reads] = snapshot }
            if byRead[2] != nil || Date() > deadline { break }
        }
        store.stop()
        let first = try XCTUnwrap(byRead[1], "a snapshot after the first config read")
        let second = try XCTUnwrap(byRead[2], "a snapshot after the second config read")
        XCTAssertEqual(first, second, "0.3 s of drift between reads is not a new snapshot")
        // A real jump (the hub's clock moved by minutes) is taken.
        let moved = HubClock(hubDate: base.addingTimeInterval(300), receivedAt: base)
        XCTAssertEqual(first.hubClock.adopting(moved), moved)
        XCTAssertEqual(first.hubClock.adopting(HubClock(hubDate: base.addingTimeInterval(1.5), receivedAt: base)), first.hubClock)
    }
}
