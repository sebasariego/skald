import XCTest
@testable import Skald

final class AutoIndenterTests: XCTestCase {
    let spaces = AutoIndenter(tabWidth: 4, insertSpaces: true)
    let tabs = AutoIndenter(tabWidth: 4, insertSpaces: false)

    func testNewlineKeepsIndentation() {
        let text = "    let x = 1" as NSString
        XCTAssertEqual(spaces.newline(at: text.length, in: text), .init(text: "\n    ", caretOffset: 5))
    }

    func testNewlineAfterOpeningBracketIndents() {
        let text = "  if x {" as NSString
        XCTAssertEqual(spaces.newline(at: text.length, in: text), .init(text: "\n      ", caretOffset: 7))
        XCTAssertEqual(tabs.newline(at: text.length, in: text), .init(text: "\n  \t", caretOffset: 4))
    }

    func testNewlineBetweenBracketsSplitsThreeWays() {
        let text = "\tf() {}" as NSString
        let insertion = spaces.newline(at: 6, in: text)
        XCTAssertEqual(insertion.text, "\n\t    \n\t")
        XCTAssertEqual(insertion.caretOffset, 6)
    }

    func testNewlineInMiddleOfLineUsesThatLinesIndent() {
        let text = "a\n  bc" as NSString
        XCTAssertEqual(spaces.newline(at: 5, in: text), .init(text: "\n  ", caretOffset: 3))
    }

    func testTabInsertionReachesNextStop() {
        XCTAssertEqual(spaces.tabInsertion(atColumn: 0), "    ")
        XCTAssertEqual(spaces.tabInsertion(atColumn: 3), " ")
        XCTAssertEqual(spaces.tabInsertion(atColumn: 4), "    ")
        XCTAssertEqual(tabs.tabInsertion(atColumn: 3), "\t")
    }

    func testColumnExpandsTabs() {
        XCTAssertEqual(spaces.column(of: 3, in: "\ta\tb" as NSString), 8)
        XCTAssertEqual(spaces.column(of: 2, in: "ab" as NSString), 2)
    }

    func testIndentAndOutdentLines() {
        XCTAssertEqual(spaces.indented("a\n\nb\n"), "    a\n\n    b\n")
        XCTAssertEqual(spaces.outdented("    a\n  b\n\tc"), "a\nb\nc")
        XCTAssertEqual(tabs.indented("a"), "\ta")
    }
}
