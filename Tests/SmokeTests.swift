import XCTest
@testable import FiestaBoardTV

final class SmokeTests: XCTestCase {
    func testBoardTablesAreLinked() {
        XCTAssertEqual(BoardTables.cell(forCode: 1, code62: .degree), .character("A"))
    }
}
