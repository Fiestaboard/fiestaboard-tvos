import SwiftUI
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

    // MARK: This TV's override

    /// The window stays the panel's to define. The TV can only ever refuse
    /// to act on it, never redefine it — so nothing here can make a board
    /// dim that the panel did not ask to dim.
    func testTheDeviceOverrideCanOnlyRefuseTheDim() {
        XCTAssertTrue(AutoDimWindow.isDimmed(overnight, at: at(23), override: .followPanel))
        XCTAssertFalse(AutoDimWindow.isDimmed(overnight, at: at(23), override: .neverDim))

        let off = AutoDim(enabled: false, start: "22:00", end: "07:00")
        XCTAssertFalse(AutoDimWindow.isDimmed(off, at: at(23), override: .followPanel))
        XCTAssertFalse(AutoDimWindow.isDimmed(off, at: at(23), override: .neverDim))
    }

    func testFollowingThePanelIsTheDefault() {
        XCTAssertTrue(AutoDimWindow.isDimmed(overnight, at: at(23)))
        XCTAssertEqual(SignageSettings(defaults: freshDefaults()).autoDimOverride, .followPanel)
    }

    func testTheOverridePersistsPerDevice() {
        let defaults = freshDefaults()
        let settings = SignageSettings(defaults: defaults)
        settings.autoDimOverride = .neverDim
        XCTAssertEqual(SignageSettings(defaults: defaults).autoDimOverride, .neverDim)
    }

    // MARK: Burn-in drift

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "tv.signage.\(UUID().uuidString)")!
    }

    /// Off unless asked for: it moves the picture, and a board that is only
    /// up for a few minutes has nothing to protect.
    func testDriftIsOffUntilItIsAskedFor() {
        let settings = SignageSettings(defaults: freshDefaults())
        XCTAssertFalse(settings.driftEnabled)
        XCTAssertEqual(settings.drift(at: Date(timeIntervalSinceReferenceDate: 123)), .zero)

        settings.driftEnabled = true
        XCTAssertNotEqual(settings.drift(at: Date(timeIntervalSinceReferenceDate: 123)), .zero)
    }

    /// A function of the clock alone, so two TVs showing the same board stay
    /// in step and a test can say where the board will be.
    func testDriftIsDeterministicAndBounded() {
        let a = BoardDrift.offset(at: Date(timeIntervalSinceReferenceDate: 400))
        let b = BoardDrift.offset(at: Date(timeIntervalSinceReferenceDate: 400))
        XCTAssertEqual(a, b)

        for seconds in stride(from: 0.0, to: BoardDrift.defaultPeriod * 2, by: 7) {
            let offset = BoardDrift.offset(at: Date(timeIntervalSinceReferenceDate: seconds))
            XCTAssertLessThanOrEqual(abs(offset.x), BoardDrift.defaultAmplitude + 0.001)
            XCTAssertLessThanOrEqual(abs(offset.y), BoardDrift.defaultAmplitude + 0.001)
        }
    }

    func testDriftRepeatsOncePerPeriodAndActuallyMoves() {
        let start = BoardDrift.offset(at: Date(timeIntervalSinceReferenceDate: 0))
        let lap = BoardDrift.offset(at: Date(timeIntervalSinceReferenceDate: BoardDrift.defaultPeriod))
        XCTAssertEqual(start.x, lap.x, accuracy: 0.0001)
        XCTAssertEqual(start.y, lap.y, accuracy: 0.0001)

        let quarter = BoardDrift.offset(at: Date(timeIntervalSinceReferenceDate: BoardDrift.defaultPeriod / 4))
        XCTAssertEqual(quarter.x, BoardDrift.defaultAmplitude, accuracy: 0.0001,
                       "a quarter lap is the far side of the path")
    }

    /// Too slow to see. A tenth of a point per second is far below the rate
    /// at which the eye reads movement at ten feet.
    func testDriftIsSlowEnoughToPassForAStillImage() {
        var previous = BoardDrift.offset(at: Date(timeIntervalSinceReferenceDate: 0))
        var worst = 0.0
        for seconds in stride(from: 1.0, through: BoardDrift.defaultPeriod, by: 1) {
            let next = BoardDrift.offset(at: Date(timeIntervalSinceReferenceDate: seconds))
            worst = max(worst, max(abs(next.x - previous.x), abs(next.y - previous.y)))
            previous = next
        }
        XCTAssertLessThan(worst, 0.2, "no more than a fifth of a point in any one second")
    }

    /// The point of the drift is that the pixels under the board change.
    /// Sample them and prove it, rather than trusting the arithmetic.
    @MainActor
    func testDriftMovesWhatIsActuallyPainted() {
        let size = CGSize(width: 200, height: 200)
        func sample(at seconds: TimeInterval) -> [Bool] {
            let offset = BoardDrift.offset(at: Date(timeIntervalSinceReferenceDate: seconds))
            let view = ZStack {
                Color.black
                Color.white
                    .frame(width: 100, height: 100)
                    .offset(x: offset.x, y: offset.y)
            }
            .frame(width: size.width, height: size.height)
            let image = RenderHarness.image(view, size: size)
            // A ring of samples straddling the white square's edges, where a
            // few points of travel decide black or white.
            return [(52, 100), (148, 100), (100, 52), (100, 148)].map { point in
                (image.pixel(x: point.0, y: point.1)?.r ?? 0) > 127
            }
        }

        let centred = sample(at: 0)                                     // offset (0, 0)
        let shifted = sample(at: BoardDrift.defaultPeriod / 4)          // offset (+8, 0)
        XCTAssertNotEqual(centred, shifted, "the board must actually move on screen")
    }
}
