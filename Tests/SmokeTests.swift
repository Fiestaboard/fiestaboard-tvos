import XCTest
@testable import FiestaBoardTV

final class SmokeTests: XCTestCase {
    func testCoreIsLinked() {
        XCTAssertEqual(CoreMarker.greeting, "FiestaBoard")
    }
}
