import XCTest
#if canImport(FiestaBoardTV)
@testable import FiestaBoardTV
#endif

final class ConnectFocusRecoveryTests: XCTestCase {
    func testFailedActivatedHubRecoversTheSameTargetAfterNativeFocusClears() {
        var recovery = ConnectFocusRecovery<String>()
        let token = recovery.begin(target: "hub-b", focused: "hub-b")
        recovery.focusChanged(to: nil)
        XCTAssertEqual(recovery.finish(token: token, failed: true, focused: nil, available: true), "hub-b")
        XCTAssertNil(recovery.finish(token: token, failed: true, focused: nil, available: true))
    }
    func testNewManualFocusCancelsOldHubRecoveryEvenIfLayoutLaterClearsIt() {
        var recovery = ConnectFocusRecovery<String>()
        let token = recovery.begin(target: "hub-a", focused: "hub-a")
        recovery.focusChanged(to: "address")
        recovery.focusChanged(to: nil)
        XCTAssertNil(recovery.finish(token: token, failed: true, focused: nil, available: true))
    }
    func testSuccessfulNavigationAndUnavailableTargetsNeverRecover() {
        var recovery = ConnectFocusRecovery<String>()
        let successful = recovery.begin(target: "hub-a", focused: "hub-a")
        XCTAssertNil(recovery.finish(token: successful, failed: false, focused: nil, available: true))
        let removed = recovery.begin(target: "hub-a", focused: "hub-a")
        XCTAssertNil(recovery.finish(token: removed, failed: true, focused: nil, available: false))
    }
    func testStaleCompletionCannotConsumeTheNewManualAttempt() {
        var recovery = ConnectFocusRecovery<String>()
        let old = recovery.begin(target: "hub-a", focused: "hub-a")
        let current = recovery.begin(target: "connect", focused: "connect")
        XCTAssertNil(recovery.finish(token: old, failed: true, focused: nil, available: true))
        XCTAssertEqual(recovery.finish(token: current, failed: true, focused: nil, available: true), "connect")
    }
    func testActivationWithoutOwningFocusAndDisappearanceDoNotStealFocus() {
        var recovery = ConnectFocusRecovery<String>()
        let unowned = recovery.begin(target: "hub-a", focused: "address")
        XCTAssertNil(recovery.finish(token: unowned, failed: true, focused: nil, available: true))
        let canceled = recovery.begin(target: "hub-a", focused: "hub-a")
        recovery.cancel()
        XCTAssertNil(recovery.finish(token: canceled, failed: true, focused: nil, available: true))
    }
    func testNewOwnerAtCompletionWinsEvenBeforeTheChangeObserverRuns() {
        var recovery = ConnectFocusRecovery<String>()
        let token = recovery.begin(target: "hub-a", focused: "hub-a")
        XCTAssertNil(recovery.finish(token: token, failed: true, focused: "address", available: true))
    }
}
