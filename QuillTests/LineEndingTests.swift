import XCTest
@testable import Quill

final class LineEndingTests: XCTestCase {
    func testDetectsFirstLineBreak() {
        XCTAssertEqual(LineEnding.detect(in: "a\nb\r\nc"), .lf)
        XCTAssertEqual(LineEnding.detect(in: "a\r\nb\nc"), .crlf)
        XCTAssertEqual(LineEnding.detect(in: "a\rb"), .cr)
        XCTAssertEqual(LineEnding.detect(in: "a\r"), .cr)
        XCTAssertEqual(LineEnding.detect(in: "no breaks"), .lf)
        XCTAssertEqual(LineEnding.detect(in: ""), .lf)
    }

    func testNormalizeToLF() {
        XCTAssertEqual(LineEnding.normalizeToLF("a\r\nb\rc\nd"), "a\nb\nc\nd")
        XCTAssertEqual(LineEnding.normalizeToLF("plain\n"), "plain\n")
    }

    func testApplyRoundTrips() {
        for ending in LineEnding.allCases {
            let onDisk = ending.apply(to: "x\ny\n")
            XCTAssertEqual(LineEnding.detect(in: onDisk), ending)
            XCTAssertEqual(LineEnding.normalizeToLF(onDisk), "x\ny\n")
        }
    }
}
