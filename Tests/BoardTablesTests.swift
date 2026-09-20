import XCTest
@testable import FiestaBoardTV

final class BoardTablesTests: XCTestCase {

    func testSpecLoads() {
        XCTAssertEqual(SpecFixture.spec.characters.count, 63)
        XCTAssertEqual(SpecFixture.spec.version, 1)
    }

    func testLettersMapToCodes1Through26() {
        XCTAssertEqual(BoardTables.cell(forCode: 1, code62: .degree), .character("A"))
        XCTAssertEqual(BoardTables.cell(forCode: 26, code62: .degree), .character("Z"))
    }

    /// The digit run is the classic trap: 1-9 are 27-35 and ZERO is 36.
    func testDigitsAreOffsetWithZeroLast() {
        XCTAssertEqual(BoardTables.cell(forCode: 27, code62: .degree), .character("1"))
        XCTAssertEqual(BoardTables.cell(forCode: 35, code62: .degree), .character("9"))
        XCTAssertEqual(BoardTables.cell(forCode: 36, code62: .degree), .character("0"))
    }

    func testCodeZeroIsBlank() {
        XCTAssertEqual(BoardTables.cell(forCode: 0, code62: .degree), .blank)
    }

    func testUndefinedCodesRenderBlank() {
        for code in SpecFixture.spec.undefinedCodes {
            XCTAssertEqual(BoardTables.cell(forCode: code, code62: .degree), .blank,
                           "code \(code) is undefined in the official table and must render blank")
        }
    }

    func testCode62IsDeviceDependent() {
        XCTAssertEqual(BoardTables.cell(forCode: 62, code62: .degree), .character("°"))
        XCTAssertEqual(BoardTables.cell(forCode: 62, code62: .heart), .character("♥"))
    }

    func testNoteDevicesGetTheHeart() {
        XCTAssertEqual(Code62Glyph.effective(deviceType: "note", configured: nil), .heart)
        XCTAssertEqual(Code62Glyph.effective(deviceType: "note_array", configured: nil), .heart)
        XCTAssertEqual(Code62Glyph.effective(deviceType: "note_array", configured: .degree), .heart,
                       "a note device's heart is not overridable — matches FiestaUI")
        XCTAssertEqual(Code62Glyph.effective(deviceType: "flagship", configured: nil), .degree)
        XCTAssertEqual(Code62Glyph.effective(deviceType: "flagship", configured: .heart), .heart)
    }

    func testColorCodesMatchTheSpec() {
        for (codeString, hex) in SpecFixture.spec.colors {
            let code = Int(codeString)!
            guard case .color(let color) = BoardTables.cell(forCode: code, code62: .degree) else {
                return XCTFail("code \(code) should be a color")
            }
            XCTAssertEqual(color.hex.lowercased(), hex.lowercased(), "color code \(code)")
        }
    }

    /// 70 and 71 are both board-black: 71 is the "filled black" variant.
    func testBothBlackCodesResolveToBoardBlack() {
        XCTAssertEqual(BoardColor(code: 70)?.hex, "#1a1a1a")
        XCTAssertEqual(BoardColor(code: 71)?.hex, "#1a1a1a")
    }

    func testOutOfRangeCodesAreBlank() {
        XCTAssertEqual(BoardTables.cell(forCode: -1, code62: .degree), .blank)
        XCTAssertEqual(BoardTables.cell(forCode: 72, code62: .degree), .blank)
        XCTAssertEqual(BoardTables.cell(forCode: 9999, code62: .degree), .blank)
    }
}
