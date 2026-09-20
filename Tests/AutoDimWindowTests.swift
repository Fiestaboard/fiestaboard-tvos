import XCTest
@testable import FiestaBoardTV

final class AutoDimWindowTests: XCTestCase {

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 19
        components.hour = hour; components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private let overnight = AutoDim(enabled: true, start: "22:00", end: "07:00")
    private let daytime = AutoDim(enabled: true, start: "09:00", end: "17:00")

    func testDisabledIsNeverDimmed() {
        let off = AutoDim(enabled: false, start: "00:00", end: "23:59")
        XCTAssertFalse(AutoDimWindow.isDimmed(off, at: at(12)))
    }

    /// The window that wraps midnight is the whole reason this is tested.
    func testOvernightWindowWrapsMidnight() {
        XCTAssertTrue(AutoDimWindow.isDimmed(overnight, at: at(23)))
        XCTAssertTrue(AutoDimWindow.isDimmed(overnight, at: at(2)))
        XCTAssertTrue(AutoDimWindow.isDimmed(overnight, at: at(6, 59)))
        XCTAssertFalse(AutoDimWindow.isDimmed(overnight, at: at(7)))
        XCTAssertFalse(AutoDimWindow.isDimmed(overnight, at: at(12)))
        XCTAssertFalse(AutoDimWindow.isDimmed(overnight, at: at(21, 59)))
    }

    func testStartIsInclusiveAndEndExclusive() {
        XCTAssertTrue(AutoDimWindow.isDimmed(overnight, at: at(22, 0)))
        XCTAssertFalse(AutoDimWindow.isDimmed(overnight, at: at(7, 0)))
    }

    func testSameDayWindowDoesNotWrap() {
        XCTAssertFalse(AutoDimWindow.isDimmed(daytime, at: at(8, 59)))
        XCTAssertTrue(AutoDimWindow.isDimmed(daytime, at: at(9)))
        XCTAssertTrue(AutoDimWindow.isDimmed(daytime, at: at(16, 59)))
        XCTAssertFalse(AutoDimWindow.isDimmed(daytime, at: at(17)))
    }

    func testAnEmptyWindowNeverDims() {
        let empty = AutoDim(enabled: true, start: "08:00", end: "08:00")
        XCTAssertFalse(AutoDimWindow.isDimmed(empty, at: at(8)))
        XCTAssertFalse(AutoDimWindow.isDimmed(empty, at: at(20)))
    }

    func testMalformedTimesNeverDim() {
        XCTAssertFalse(AutoDimWindow.isDimmed(AutoDim(enabled: true, start: "nonsense", end: "07:00"),
                                              at: at(23)))
        XCTAssertFalse(AutoDimWindow.isDimmed(AutoDim(enabled: true, start: "25:00", end: "07:00"),
                                              at: at(23)))
    }
}
