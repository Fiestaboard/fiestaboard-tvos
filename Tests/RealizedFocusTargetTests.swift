import XCTest
@testable import FiestaBoardTV

/// The Panels focus walk assigns focus only to a realised card
/// (`program/status/tv-panels-flake.md`). Focusing a `LazyVGrid` card whose
/// row isn't realised yet is dropped by SwiftUI; the old code relied on a
/// single `Task.yield()` after `scrollTo` and flaked whenever realisation
/// took longer (viewport height, card height, load).
final class RealizedFocusTargetTests: XCTestCase {

    func testARequestForARealisedCardFocusesAtOnce() {
        var target = RealizedFocusTarget()
        target.cardAppeared("a")
        XCTAssertEqual(target.request("a"), "a")
        XCTAssertNil(target.pending)
    }

    func testARequestForAnUnrealisedCardWaitsForItsAppearance() {
        var target = RealizedFocusTarget()
        XCTAssertNil(target.request("z"), "not realised yet: don't hand SwiftUI a missing view")
        XCTAssertEqual(target.pending, "z")
        XCTAssertNil(target.cardAppeared("y"), "another card appearing doesn't take the focus")
        XCTAssertEqual(target.cardAppeared("z"), "z", "the card gets focus as it is realised")
        XCTAssertNil(target.pending)
    }

    func testADisappearedCardIsNoLongerRealised() {
        var target = RealizedFocusTarget()
        target.cardAppeared("a")
        target.cardDisappeared("a")
        XCTAssertNil(target.request("a"))
        XCTAssertEqual(target.cardAppeared("a"), "a")
    }

    func testANewerRequestSupersedesAPendingOne() {
        var target = RealizedFocusTarget()
        _ = target.request("old")
        _ = target.request("new")
        XCTAssertNil(target.cardAppeared("old"), "a superseded request must not steal focus later")
        XCTAssertEqual(target.cardAppeared("new"), "new")
    }

    func testCancellingDropsThePendingRequest() {
        var target = RealizedFocusTarget()
        _ = target.request("z")
        target.cancel()
        XCTAssertNil(target.cardAppeared("z"))
    }
}
