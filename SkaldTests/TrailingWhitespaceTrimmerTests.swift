import XCTest
@testable import Skald

final class TrailingWhitespaceTrimmerTests: XCTestCase {
    func testFindsRunsBeforeNewlinesAndAtEnd() {
        let ranges = TrailingWhitespaceTrimmer.ranges(in: "a  \nb\n\t\nc \t" as NSString)
        XCTAssertEqual(ranges, [NSRange(location: 1, length: 2), NSRange(location: 6, length: 1), NSRange(location: 9, length: 2)])
    }

    @MainActor
    func testTrimsStorageInOneBatch() {
        let storage = NSTextStorage(string: "x \ny\t\n")
        XCTAssertEqual(TrailingWhitespaceTrimmer.trim(storage), 2)
        XCTAssertEqual(storage.string, "x\ny\n")
        XCTAssertEqual(TrailingWhitespaceTrimmer.trim(storage), 0)
    }
}
