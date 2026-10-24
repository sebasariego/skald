import XCTest
@testable import Skald

final class LineIndexTests: XCTestCase {
    func testInitialScan() {
        let index = LineIndex(text: "a\nbb\n\nccc")
        XCTAssertEqual(index.lineStarts, [0, 2, 5, 6])
        XCTAssertEqual(index.lineCount, 4)
        XCTAssertEqual(index.lineNumber(forOffset: 0), 0)
        XCTAssertEqual(index.lineNumber(forOffset: 1), 0)
        XCTAssertEqual(index.lineNumber(forOffset: 2), 1)
        XCTAssertEqual(index.lineNumber(forOffset: 5), 2)
        XCTAssertEqual(index.lineNumber(forOffset: 99), 3)
        XCTAssertEqual(index.range(ofLine: 1, totalLength: 9), NSRange(location: 2, length: 2))
        XCTAssertEqual(index.range(ofLine: 3, totalLength: 9), NSRange(location: 6, length: 3))
    }

    func testEmptyAndTrailingNewline() {
        XCTAssertEqual(LineIndex(text: "").lineStarts, [0])
        XCTAssertEqual(LineIndex(text: "x\n").lineStarts, [0, 2])
    }

    func testIncrementalEditsMatchRescan() {
        var text = "one\ntwo\nthree\n"
        var index = LineIndex(text: text as NSString)

        func apply(_ range: NSRange, _ replacement: String, file: StaticString = #filePath, line: UInt = #line) {
            index.replaceCharacters(in: range, with: replacement as NSString)
            text = (text as NSString).replacingCharacters(in: range, with: replacement)
            XCTAssertEqual(index, LineIndex(text: text as NSString), "after replacing \(range) with \(replacement.debugDescription)", file: file, line: line)
        }

        apply(NSRange(location: 3, length: 0), "\n")           // split a line
        apply(NSRange(location: 0, length: 4), "")             // delete the new first line
        apply(NSRange(location: 4, length: 4), "2\n2\n2\n")    // replace one line with three
        apply(NSRange(location: 0, length: text.utf16.count), "")  // clear everything
        apply(NSRange(location: 0, length: 0), "a\nb")
        apply(NSRange(location: 1, length: 1), "")             // join lines by deleting "\n"
        apply(NSRange(location: 0, length: 0), "\n\n")
        apply(NSRange(location: 1, length: 2), "X")            // remove a "\n" and a char
    }

    func testLargeFileScanIsFast() {
        let line = String(repeating: "x", count: 60) + "\n"
        let text = String(repeating: line, count: 80_000) as NSString // ~4.9 MB
        measure {
            let index = LineIndex(text: text)
            XCTAssertEqual(index.lineCount, 80_001)
        }
    }
}
