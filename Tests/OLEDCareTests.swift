import XCTest
#if canImport(FiestaBoardTV)
@testable import FiestaBoardTV
#else
@testable import OLEDCore
#endif

final class OLEDCareTests: XCTestCase {
    func testDefaultsAndOLEDAnswerDoNotEnableProtection() {
        var c = OLEDCareConfiguration()
        for answer in OLEDAnswer.allCases {
            c.answer = answer
            let out = OLEDCarePolicy.evaluate(c, minute: 720)
            XCTAssertEqual(out.brightness, 1)
            XCTAssertFalse(out.resting)
            XCTAssertTrue(out.keepAwake)
            XCTAssertEqual(out.placement, .center)
        }
    }
    func testLegacyMigrationAndPersistence() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "fiestaboard.signage.driftEnabled")
        defaults.set("neverDim", forKey: "fiestaboard.signage.autoDimOverride")
        let store = OLEDCareStore(defaults: defaults)
        var c = store.load()
        XCTAssertTrue(c.movement)
        XCTAssertEqual(c.nightMode, .never)
        c.brightness = 50; c.nightMode = .custom; c.nightLevel = 25
        c.restEnabled = true; c.restStart = 60; c.restEnd = 120
        c.breaksEnabled = true; c.breakInterval = 30; c.breakDuration = 10
        c.rotationEnabled = true; c.placements = [.upperLeft, .lowerRight]; c.rotationInterval = 15
        c.disconnected = .rest; c.disconnectDelay = 15; c.allowScreensaver = true
        c.answer = .yes; c.invitationDismissed = true; c.movementRange = 24
        store.save(c)
        XCTAssertEqual(OLEDCareStore(defaults: defaults).load(), c)
        XCTAssertTrue(defaults.bool(forKey: "fiestaboard.signage.driftEnabled"))
    }
    func testMalformedValuesNormalizeIndividually() {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["brightness": 50, "nightMode": "future", "nightLevel": -20,
                      "restStart": 9000, "breakInterval": 0, "movementRange": 90,
                      "placements": ["upperLeft", "future", "upperLeft"]], forKey: OLEDCareStore.key)
        let c = OLEDCareStore(defaults: defaults).load()
        XCTAssertEqual(c.brightness, 50); XCTAssertEqual(c.nightMode, .followPanel)
        XCTAssertEqual(c.nightLevel, 35); XCTAssertEqual(c.restStart, 1320)
        XCTAssertEqual(c.breakInterval, 60); XCTAssertEqual(c.movementRange, 8)
        XCTAssertEqual(c.placements, [.upperLeft])
    }
    func testNightBoundariesMultiplicationAndLegacyLevel() {
        var c = OLEDCareConfiguration()
        XCTAssertEqual(OLEDCarePolicy.evaluate(c, minute: 0, panelDimmed: true).brightness, 0.35)
        c.nightMode = .custom; c.brightness = 50
        for minute in [1320, 0, 419] { XCTAssertEqual(OLEDCarePolicy.evaluate(c, minute: minute).brightness, 0.175) }
        for minute in [420, 1319] { XCTAssertEqual(OLEDCarePolicy.evaluate(c, minute: minute).brightness, 0.5) }
        c.nightStart = 420; c.nightEnd = 420
        XCTAssertEqual(OLEDCarePolicy.evaluate(c, minute: 420).brightness, 0.5)
    }
    func testRestPrecedenceAndWakeExpiry() {
        var c = OLEDCareConfiguration(); c.restEnabled = true; c.brightness = 25
        var s = OLEDCareSession()
        var out = s.update(c, now: 10, minute: 0, foreground: true, viewing: true, unavailable: false)
        XCTAssertTrue(out.resting); XCTAssertFalse(out.keepAwake); XCTAssertEqual(out.brightness, 0)
        XCTAssertTrue(s.interact(now: 10))
        out = s.update(c, now: 309, minute: 0, foreground: true, viewing: true, unavailable: false)
        XCTAssertFalse(out.resting)
        XCTAssertTrue(s.update(c, now: 310, minute: 0, foreground: true, viewing: true, unavailable: false).resting)
        c.restStart = c.restEnd
        XCTAssertFalse(s.update(c, now: 311, minute: 0, foreground: true, viewing: true, unavailable: false).resting)
    }
    func testBreakClockIgnoresPollsAndPausesInBackground() {
        var c = OLEDCareConfiguration(); c.breaksEnabled = true; c.breakInterval = 30; c.breakDuration = 1
        var s = OLEDCareSession()
        for second in stride(from: 0, through: 1799, by: 1) {
            XCTAssertFalse(s.update(c, now: Double(second), minute: 720, foreground: true, viewing: true, unavailable: false).resting)
        }
        XCTAssertTrue(s.update(c, now: 1800, minute: 720, foreground: true, viewing: true, unavailable: false).resting)
        XCTAssertTrue(s.interact(now: 1800))
        XCTAssertFalse(s.update(c, now: 1801, minute: 720, foreground: true, viewing: true, unavailable: false).resting)
        _ = s.update(c, now: 1810, minute: 720, foreground: false, viewing: true, unavailable: false)
        XCTAssertFalse(s.update(c, now: 10000, minute: 720, foreground: true, viewing: true, unavailable: false).resting)
        XCTAssertFalse(s.update(c, now: 10001, minute: 720, foreground: true, viewing: true, unavailable: false).resting)
    }
    func testDisconnectTimerSurvivesRetriesAndRecoveryResetsIt() {
        var c = OLEDCareConfiguration(); c.disconnected = .rest; c.disconnectDelay = 1
        var s = OLEDCareSession()
        _ = s.update(c, now: 0, minute: 720, foreground: true, viewing: true, unavailable: true)
        XCTAssertFalse(s.update(c, now: 59, minute: 720, foreground: true, viewing: true, unavailable: true).resting)
        XCTAssertTrue(s.update(c, now: 60, minute: 720, foreground: true, viewing: true, unavailable: true).resting)
        XCTAssertFalse(s.update(c, now: 61, minute: 720, foreground: true, viewing: true, unavailable: false).resting)
        XCTAssertFalse(s.update(c, now: 62, minute: 720, foreground: true, viewing: true, unavailable: true).resting)
        c.disconnected = .dim; c.brightness = 50
        XCTAssertEqual(s.update(c, now: 122, minute: 720, foreground: true, viewing: true, unavailable: true).brightness, 0.175)
    }
    func testRotationNeedsTwoPositionsAndUsesElapsedTime() {
        var c = OLEDCareConfiguration(); c.rotationEnabled = true; c.placements = [.upperLeft]
        XCTAssertEqual(OLEDCarePolicy.evaluate(c, minute: 720, elapsed: 600).placement, .center)
        c.placements = [.upperLeft, .lowerRight]
        XCTAssertEqual(OLEDCarePolicy.evaluate(c, minute: 720, elapsed: 299).placement, .upperLeft)
        XCTAssertEqual(OLEDCarePolicy.evaluate(c, minute: 720, elapsed: 300).placement, .lowerRight)
        XCTAssertEqual(OLEDCarePolicy.evaluate(c, minute: 720, elapsed: 600).placement, .upperLeft)
    }
    func testProtectedGeometryContainsWiderMovementAndRotation() {
        var c = OLEDCareConfiguration(); c.movement = true; c.movementRange = 24
        for placement in OLEDPlacement.allCases {
            let g = OLEDCareGeometry(width: 1920, height: 1080, config: c, rotating: true, placement: placement, elapsed: 300, reduceMotion: false)
            XCTAssertEqual(g.width, 1497.6, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(g.x - g.width / 2, 0)
            XCTAssertLessThanOrEqual(g.x + g.width / 2, 1920)
            XCTAssertGreaterThanOrEqual(g.y - g.height / 2, 0)
            XCTAssertLessThanOrEqual(g.y + g.height / 2, 1080)
        }
        let still = OLEDCareGeometry(width: 1920, height: 1080, config: c, rotating: false, placement: .center, elapsed: 300, reduceMotion: true)
        XCTAssertEqual(still.x, 960); XCTAssertEqual(still.y, 540)
        c.movement = false
        XCTAssertEqual(OLEDCareGeometry(width: 1920, height: 1080, config: c, rotating: false, placement: .center, elapsed: 300, reduceMotion: false).width, 1920)
    }
    func testIdleInhibitionAndAutomaticBreakEnd() {
        var c = OLEDCareConfiguration()
        XCTAssertFalse(OLEDCarePolicy.evaluate(c, minute: 720, foreground: false).keepAwake)
        XCTAssertFalse(OLEDCarePolicy.evaluate(c, minute: 720, viewing: false).keepAwake)
        c.allowScreensaver = true
        XCTAssertFalse(OLEDCarePolicy.evaluate(c, minute: 720).keepAwake)
        c.breaksEnabled = true; c.breakInterval = 30; c.breakDuration = 1
        var s = OLEDCareSession()
        _ = s.update(c, now: 0, minute: 720, foreground: true, viewing: true, unavailable: false)
        XCTAssertTrue(s.update(c, now: 1800, minute: 720, foreground: true, viewing: true, unavailable: false).resting)
        XCTAssertFalse(s.update(c, now: 1860, minute: 720, foreground: true, viewing: true, unavailable: false).resting)
        XCTAssertFalse(s.interact(now: 1860))
    }

    func testBackgroundPausesPartialIntervalAndCancelsActiveBreak() {
        var c = OLEDCareConfiguration(); c.breaksEnabled = true; c.breakInterval = 30; c.breakDuration = 5
        var s = OLEDCareSession()
        _ = s.update(c, now: 0, minute: 720, foreground: true, viewing: true, unavailable: false)
        _ = s.update(c, now: 900, minute: 720, foreground: true, viewing: true, unavailable: false)
        _ = s.update(c, now: 900, minute: 720, foreground: false, viewing: true, unavailable: false)
        XCTAssertFalse(s.update(c, now: 10000, minute: 720, foreground: true, viewing: true, unavailable: false).resting)
        XCTAssertTrue(s.update(c, now: 10900, minute: 720, foreground: true, viewing: true, unavailable: false).resting)
        _ = s.update(c, now: 10900, minute: 720, foreground: false, viewing: true, unavailable: false)
        XCTAssertFalse(s.update(c, now: 20000, minute: 720, foreground: true, viewing: true, unavailable: false).resting)
        XCTAssertFalse(s.update(c, now: 20001, minute: 720, foreground: true, viewing: true, unavailable: false).resting)
    }

    func testOrdinaryRemoteInputDoesNotPostponeBreak() {
        var c = OLEDCareConfiguration(); c.breaksEnabled = true; c.breakInterval = 30
        var s = OLEDCareSession()
        _ = s.update(c, now: 0, minute: 720, foreground: true, viewing: true, unavailable: false)
        _ = s.update(c, now: 1740, minute: 720, foreground: true, viewing: true, unavailable: false)
        XCTAssertFalse(s.interact(now: 1740))
        XCTAssertTrue(s.update(c, now: 1800, minute: 720, foreground: true, viewing: true, unavailable: false).resting)
    }
    func testRemoteTemporarilyResumesOutageDimming() {
        var c = OLEDCareConfiguration(); c.disconnected = .dim; c.disconnectDelay = 1
        var s = OLEDCareSession()
        _ = s.update(c, now: 0, minute: 720, foreground: true, viewing: true, unavailable: true)
        XCTAssertEqual(s.update(c, now: 60, minute: 720, foreground: true, viewing: true, unavailable: true).brightness, 0.35)
        XCTAssertFalse(s.interact(now: 60))
        XCTAssertEqual(s.update(c, now: 359, minute: 720, foreground: true, viewing: true, unavailable: true).brightness, 1)
        XCTAssertEqual(s.update(c, now: 360, minute: 720, foreground: true, viewing: true, unavailable: true).brightness, 0.35)
    }

}
