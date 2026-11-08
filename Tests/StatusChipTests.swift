import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// A6b (4.6 UI): when the read-only status chip shows, what it is drawn as,
/// and what VoiceOver hears. 07b `tvOS / Status chip` `152:4203`; A7
/// `I166:204936;149:182603`; strip `166:206938`; DD22, DD25.
final class StatusChipPresenterTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_794_104_280) // 2026-11-08T02:18:00Z

    private func chip(_ kind: StatusChipKind, _ text: String, badge: String? = nil, persistent: Bool = false) -> StatusChipContent {
        StatusChipContent(kind: kind, badge: badge, text: text, persistent: persistent)
    }

    private lazy var override = chip(.override, "2h 43m left · Holds until 9:00 PM", badge: "Override")
    private lazy var schedule = chip(.schedule, "Schedule · next change 9:00 PM")
    private lazy var unreachable = chip(.hubUnreachable, "Hub unreachable · showing the last update", persistent: true)
    private lazy var reconnected = chip(.reconnected, "Reconnected")

    func testAChangeShowsTheChipOnItsOwnForSixSeconds() {
        var p = StatusChipPresenter()
        XCTAssertTrue(p.update(schedule, at: t0), "the first chip is a change")
        XCTAssertTrue(p.standaloneVisible(at: t0, overlayVisible: false))
        XCTAssertTrue(p.standaloneVisible(at: t0.addingTimeInterval(5.9), overlayVisible: false))
        XCTAssertFalse(p.standaloneVisible(at: t0.addingTimeInterval(6), overlayVisible: false))
        XCTAssertEqual(p.nextDeadline, t0.addingTimeInterval(StatusChipPresenter.transient))
        XCTAssertFalse(p.update(schedule, at: t0.addingTimeInterval(8)), "the same chip again is not a change")
        XCTAssertFalse(p.standaloneVisible(at: t0.addingTimeInterval(8), overlayVisible: false))
        XCTAssertTrue(p.update(override, at: t0.addingTimeInterval(10)))
        XCTAssertTrue(p.standaloneVisible(at: t0.addingTimeInterval(15), overlayVisible: false), "re-shown on change")
    }

    func testTheCountdownTickingIsNotAChange() {
        var p = StatusChipPresenter()
        XCTAssertTrue(p.update(override, at: t0))
        let later = chip(.override, "2h 42m left · Holds until 9:00 PM", badge: "Override")
        XCTAssertFalse(p.update(later, at: t0.addingTimeInterval(60)))
        XCTAssertEqual(p.chip, later, "the text still updates")
        let moved = chip(.override, "1h 0m left · Holds until 10:00 PM", badge: "Override")
        XCTAssertTrue(p.update(moved, at: t0.addingTimeInterval(70)), "a new end is a new override")
    }

    func testWithTheOverlayUpTheChipIsInTheBarNotOnItsOwn() {
        var p = StatusChipPresenter()
        _ = p.update(unreachable, at: t0)
        XCTAssertFalse(p.standaloneVisible(at: t0, overlayVisible: true))
        XCTAssertTrue(p.standaloneVisible(at: t0.addingTimeInterval(600), overlayVisible: false), "persistent")
    }

    func testPersistentChipsStay() {
        var p = StatusChipPresenter()
        _ = p.update(chip(.silenced, "Silenced until 7:00 AM · showing a message", persistent: true), at: t0)
        XCTAssertTrue(p.standaloneVisible(at: t0.addingTimeInterval(3600), overlayVisible: false))
        XCTAssertNil(p.nextDeadline, "nothing to time out")
    }

    /// An outage and recovery says "Hub unreachable", then "Reconnected" for
    /// 3 s (DD22), and the chip from before the outage coming back is not news.
    func testAnOutageRoundTrip() {
        var p = StatusChipPresenter()
        _ = p.update(schedule, at: t0)
        XCTAssertTrue(p.update(unreachable, at: t0.addingTimeInterval(20)))
        XCTAssertFalse(p.update(unreachable, at: t0.addingTimeInterval(22)))
        XCTAssertTrue(p.update(reconnected, at: t0.addingTimeInterval(40)))
        XCTAssertTrue(p.standaloneVisible(at: t0.addingTimeInterval(42.9), overlayVisible: false))
        XCTAssertFalse(p.standaloneVisible(at: t0.addingTimeInterval(43), overlayVisible: false), "Reconnected is 3 s")
        XCTAssertFalse(p.update(schedule, at: t0.addingTimeInterval(43)), "the same status as before the outage")
        XCTAssertFalse(p.standaloneVisible(at: t0.addingTimeInterval(43), overlayVisible: false))
        XCTAssertTrue(p.update(override, at: t0.addingTimeInterval(44)), "a status that changed during the outage is")
    }

    func testNoChipIsNotAnnounced() {
        var p = StatusChipPresenter()
        XCTAssertFalse(p.update(nil, at: t0))
        _ = p.update(schedule, at: t0)
        XCTAssertFalse(p.update(nil, at: t0.addingTimeInterval(1)))
        XCTAssertFalse(p.standaloneVisible(at: t0.addingTimeInterval(1), overlayVisible: false))
    }

    /// Strip `166:206938`: "Living room TV: override until 9:00 PM". The
    /// announcement is the strip's phrase, not the chip's countdown line.
    func testWhatVoiceOverSays() {
        func say(_ c: StatusChipContent) -> String { StatusChipPresenter.spoken(c, panelName: "Living room TV") }
        XCTAssertEqual(say(override), "Living room TV: override until 9:00 PM")
        XCTAssertEqual(say(chip(.override, "Holds until canceled", badge: "Override")), "Living room TV: override until canceled")
        XCTAssertEqual(say(reconnected), "Living room TV: reconnected")
        XCTAssertEqual(say(unreachable), "Living room TV: hub unreachable, showing the last update")
        XCTAssertEqual(say(schedule), "Living room TV: schedule, next change 9:00 PM")
        XCTAssertEqual(StatusChipPresenter.label(override), "Override, 2h 43m left · Holds until 9:00 PM",
                       "the chip's own element still reads its words")
    }

    /// The first status on opening the viewer is news (decided, both TVs).
    func testTheFirstStatusOnOpeningIsNews() {
        var p = StatusChipPresenter()
        XCTAssertTrue(p.update(override, at: t0))
        XCTAssertTrue(p.standaloneVisible(at: t0, overlayVisible: false))
    }

    /// A schedule hand-off: the next change passes ("Schedule"), then the next
    /// config read brings the new one. Neither is news: one board on its
    /// schedule throughout, so no double announcement within 10 s.
    func testAScheduleHandOffIsNotNews() {
        var p = StatusChipPresenter()
        XCTAssertTrue(p.update(schedule, at: t0))
        XCTAssertFalse(p.update(chip(.schedule, "Schedule"), at: t0.addingTimeInterval(60)))
        let next = chip(.schedule, "Schedule · next change 1:00 AM")
        XCTAssertFalse(p.update(next, at: t0.addingTimeInterval(68)))
        XCTAssertEqual(p.chip, next, "the words still update")
        XCTAssertFalse(p.standaloneVisible(at: t0.addingTimeInterval(68), overlayVisible: false))
    }
}

/// Each chip names its 07b variant, in each material.
final class StatusChipVariantTests: XCTestCase {
    private func variant(_ kind: StatusChipKind, _ text: String) -> StatusChipVariant {
        StatusChipVariant(StatusChipContent(kind: kind, badge: nil, text: text, persistent: false))
    }

    func testEveryDD22KindHasItsVariant() {
        XCTAssertEqual(variant(.override, "2h 43m left · Holds until 9:00 PM"), .override)
        XCTAssertEqual(variant(.override, "Holds until canceled"), .overrideUntilCanceled)
        XCTAssertEqual(variant(.silenced, "Silenced until 7:00 AM · showing a message"), .silencedMessage)
        XCTAssertEqual(variant(.silenced, "Silenced until 7:00 AM · showing the last update"), .silencedFreeze)
        XCTAssertEqual(variant(.silenced, "Silenced until 7:00 AM · showing the silence page"), .silencedPage)
        XCTAssertEqual(variant(.silenced, "Silenced"), .silencedMessage)
        XCTAssertEqual(variant(.paused, "Paused · showing the last update"), .paused)
        XCTAssertEqual(variant(.hubUnreachable, "Hub unreachable · showing the last update"), .hubUnreachable)
        XCTAssertEqual(variant(.schedule, "Schedule · next change 9:00 PM"), .schedule)
        XCTAssertEqual(variant(.schedule, "Schedule"), .scheduleNoNextChange)
        XCTAssertEqual(variant(.reconnected, "Reconnected"), .reconnected)
    }

    #if DEBUG
    func testEachVariantMapsToThe07bSet() {
        let table: [(StatusChipVariant, [String])] = [
            (.override, ["152:4184", "250:110500", "250:110504"]),
            (.overrideUntilCanceled, ["275:138737", "275:138755", "275:138773"]),
            (.silencedMessage, ["152:4188", "250:110508", "250:110511"]),
            (.silencedFreeze, ["275:138741", "275:138759", "275:138777"]),
            (.silencedPage, ["275:138745", "275:138763", "275:138781"]),
            (.paused, ["152:4192", "250:110514", "250:110517"]),
            (.hubUnreachable, ["152:4196", "250:110520", "250:110523"]),
            (.schedule, ["152:4200", "250:110526", "250:110529"]),
            (.scheduleNoNextChange, ["275:138752", "275:138770", "275:138788"]),
            (.reconnected, ["275:138749", "275:138767", "275:138785"]),
        ]
        for (variant, nodes) in table {
            XCTAssertEqual([variant.node(.liquidGlass), variant.node(.regularMaterial), variant.node(.opaque)], nodes, "\(variant)")
        }
    }
    #endif
}

/// The #23 review fold-ins (S1, S3, N3) and the A6a carry (N1, `keepingStatus`).
final class StatusChipFoldInTests: XCTestCase {

    /// S1: a surface outside any `ViewerGlassContainer` (the standalone chip)
    /// still goes opaque under Reduce Transparency.
    func testReduceTransparencyWinsOutsideAContainer() {
        for inherited in [ViewerMaterial.liquidGlass, .regularMaterial, .opaque] {
            for explicit in [nil, ViewerMaterial.liquidGlass, .regularMaterial] {
                XCTAssertEqual(ViewerMaterial.effective(explicit: explicit, inherited: inherited, reduceTransparency: true), .opaque)
            }
        }
        XCTAssertEqual(ViewerMaterial.effective(explicit: nil, inherited: .regularMaterial, reduceTransparency: false), .regularMaterial)
        XCTAssertEqual(ViewerMaterial.effective(explicit: .opaque, inherited: .liquidGlass, reduceTransparency: false), .opaque)
    }

    /// S3: the pre-26 regular material carries a dark tint strong enough that
    /// the muted subtitle keeps 4.5:1 even over a white board (worst case,
    /// before the material's own darkening).
    func testTheRegularTintKeepsTheSubtitleReadable() {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) }
        let a = ViewerMaterial.regularTintOpacity
        let bg = FiestaTokenValues.Dark.background
        let ground = luminance(bg.red * a + (1 - a), bg.green * a + (1 - a), bg.blue * a + (1 - a))
        let muted = FiestaTokenValues.Dark.mutedForeground
        let text = luminance(muted.red, muted.green, muted.blue)
        XCTAssertGreaterThanOrEqual((text + 0.05) / (ground + 0.05), 4.5)
        XCTAssertLessThan(a, 1, "still a material, not a card")
    }

    /// N1 (Jev check_fallthrough): silence ends on the hub's clock, like an override.
    func testSilenceEndsOnTheHubClock() {
        let until = Date(timeIntervalSince1970: 1_794_150_000)
        let status = PanelStatus(mode: .schedule, scheduleEnabled: true, overrideActive: false, overrideExpiresAt: nil,
                                 overrideStartedAt: nil, silenced: true, silencedUntil: until, silenceMode: .indicator, paused: false)
        XCTAssertEqual(PanelStatusChip.chip(status: status, hubNow: until.addingTimeInterval(-1))?.kind, .silenced)
        XCTAssertEqual(PanelStatusChip.chip(status: status, hubNow: until)?.kind, .schedule, "over: fall through")
        var open = status
        open.silencedUntil = nil
        XCTAssertEqual(PanelStatusChip.chip(status: open, hubNow: until.addingTimeInterval(9999))?.kind, .silenced, "no end: still silenced")
    }

    /// A6a nit: a panel that has its own status keeps it.
    func testKeepingStatusPrefersItsOwn() throws {
        func panel(_ status: String) throws -> Panel {
            try JSONDecoder().decode(Panel.self, from: Data(#"{"id":"p","name":"P","board_id":"b","status":\#(status)}"#.utf8))
        }
        let paused = try panel(#"{"mode":"manual","schedule_enabled":false,"override_active":false,"silenced":false,"paused":true}"#)
        let manual = try panel(#"{"mode":"manual","schedule_enabled":false,"override_active":false,"silenced":false,"paused":false}"#)
        XCTAssertEqual(paused.keepingStatus(of: manual).status?.paused, true)
        XCTAssertEqual(try panel("null").keepingStatus(of: paused).status?.paused, true)
    }
}

/// The viewer model drives the chip from its snapshots.
@MainActor
final class ViewerStatusChipTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_794_104_280) // 2026-11-08T02:18:00Z
    private var heard: [String] = []
    private var restore: Announce.Sink?

    override func setUp() {
        super.setUp()
        restore = Announce.sink
        Announce.sink = { [weak self] kind, message in
            if kind == .announcement, let message { self?.heard.append(message) }
        }
    }

    override func tearDown() {
        if let restore { Announce.sink = restore }
        super.tearDown()
    }

    private func model() -> ViewerModel {
        let app = AppModel(connection: ConnectionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, credentials: InMemoryCredentialStore()))
        return ViewerModel(app: app, ref: "p", signage: SignageSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
                           isVoiceOverRunning: { false }, now: { [unowned self] in self.clock })
    }

    private func panel(_ status: String?) throws -> Panel {
        let json = #"{"id":"p","name":"Living room TV","board_id":"b","rows":1,"cols":1"# + (status.map { #","status":"# + $0 } ?? "") + "}"
        return try JSONDecoder().decode(Panel.self, from: Data(json.utf8))
    }

    private let schedule = #"{"mode":"schedule","schedule_enabled":true,"override_active":false,"silenced":false,"paused":false}"#
    private let override = #"{"mode":"override","schedule_enabled":false,"override_active":true,"override_expires_at":"2026-11-08T05:00:37+00:00","silenced":false,"paused":false}"#

    private func snapshot(_ panel: Panel, _ connection: ConnectionState = .live) -> PanelSnapshot {
        PanelSnapshot(panel: panel, cells: [[.blank]], rows: 1, cols: 1, connection: connection, dimmed: false, deleted: false)
    }

    func testTheChipFollowsTheSnapshotAndHidesAfterSixSeconds() throws {
        let m = model()
        m.apply(snapshot(try panel(schedule)))
        XCTAssertEqual(m.statusChip?.kind, .schedule)
        XCTAssertTrue(m.chipStandaloneVisible)
        clock += 6.1
        m.refreshChip()
        XCTAssertFalse(m.chipStandaloneVisible, "6 s on its own")
        XCTAssertEqual(m.statusChip?.kind, .schedule, "still there for the overlay bar")
        m.apply(snapshot(try panel(override)))
        XCTAssertEqual(m.statusChip?.kind, .override)
        XCTAssertTrue(m.chipStandaloneVisible, "re-shown on change")
        m.showOverlay()
        XCTAssertFalse(m.chipStandaloneVisible, "in the bar while the overlay is up")
        m.hideOverlay()
    }

    func testVoiceOverHearsEachChangeOnce() throws {
        let m = model()
        m.apply(snapshot(try panel(override)))
        m.apply(snapshot(try panel(override)))
        clock += 61
        m.apply(snapshot(try panel(override)))
        XCTAssertEqual(heard, ["Living room TV: override until " + Self.time("2026-11-08T05:00:37Z")])
        m.apply(snapshot(try panel(schedule)))
        XCTAssertEqual(heard.count, 2)
        XCTAssertEqual(heard.last, "Living room TV: schedule")
    }

    func testAnOutageThenRecoveryReadsReconnected() throws {
        let m = model()
        let p = try panel(schedule)
        m.apply(snapshot(p))
        m.apply(snapshot(p, .stale))
        XCTAssertEqual(m.statusChip?.kind, .hubUnreachable)
        clock += 60
        m.refreshChip()
        XCTAssertTrue(m.chipStandaloneVisible, "unreachable persists")
        m.apply(snapshot(p))
        XCTAssertEqual(m.statusChip?.kind, .reconnected)
        XCTAssertTrue(m.chipStandaloneVisible)
        clock += 3.1
        m.refreshChip()
        XCTAssertEqual(m.statusChip?.kind, .schedule)
        XCTAssertFalse(m.chipStandaloneVisible, "the status from before the outage is not news")
        XCTAssertEqual(heard, ["Living room TV: schedule", "Living room TV: hub unreachable, showing the last update",
                               "Living room TV: reconnected"])
    }

    /// #25 review must-fix: a removed board (or a deleted panel) hides the
    /// hub's status, never the connection: an outage still shows and says
    /// "Hub unreachable", and "Reconnected" follows.
    func testARemovedBoardStillSaysHubUnreachable() throws {
        let m = model()
        let missing = try JSONDecoder().decode(Panel.self, from: Data(
            #"{"id":"p","name":"Living room TV","board_id":"b","board_missing":true,"status":null}"#.utf8))
        m.apply(snapshot(missing))
        XCTAssertNil(m.statusChip)
        m.apply(snapshot(missing, .stale))
        XCTAssertEqual(m.statusChip?.kind, .hubUnreachable)
        XCTAssertTrue(m.chipStandaloneVisible)
        XCTAssertEqual(heard, ["Living room TV: hub unreachable, showing the last update"])
        m.apply(snapshot(missing))
        XCTAssertEqual(m.statusChip?.kind, .reconnected)
        XCTAssertEqual(heard.count, 2)
    }

    func testADeletedPanelHidesItsStatusButNotAnOutage() throws {
        let m = model()
        let p = try panel(override)
        let deleted = PanelSnapshot(panel: p, cells: [[.blank]], rows: 1, cols: 1, connection: .live, dimmed: false, deleted: true)
        m.apply(deleted)
        XCTAssertNil(m.statusChip, "no hub status for a panel that is gone")
        m.apply(PanelSnapshot(panel: p, cells: [[.blank]], rows: 1, cols: 1, connection: .stale, dimmed: false, deleted: true))
        XCTAssertEqual(m.statusChip?.kind, .hubUnreachable)
    }

    /// Strip `166:206938`: the fade is 0.3 s, and instant under Reduce Motion.
    func testTheChipFadeIsInstantUnderReduceMotion() {
        XCTAssertNil(ViewerScreen.chipFade(reduceMotion: true))
        XCTAssertEqual(ViewerScreen.chipFade(reduceMotion: false), .easeInOut(duration: 0.3))
    }

    func testAnOldHubShowsNoChip() throws {
        let m = model()
        m.apply(snapshot(try panel(nil)))
        XCTAssertNil(m.statusChip)
        XCTAssertFalse(m.chipStandaloneVisible)
        XCTAssertTrue(heard.isEmpty)
    }

    private static func time(_ iso: String) -> String {
        PanelStatusChip.time(ISO8601DateFormatter().date(from: iso)!, .current)
    }
}
