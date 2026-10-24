import XCTest
@testable import Quill

final class BracketMatcherTests: XCTestCase {
    func testMatchesNestedPairs() {
        let text = "f(a[1], {b: (c)})" as NSString
        XCTAssertEqual(BracketMatcher.pair(forBracketAt: 1, in: text), .init(open: 1, close: 16))
        XCTAssertEqual(BracketMatcher.pair(forBracketAt: 16, in: text), .init(open: 1, close: 16))
        XCTAssertEqual(BracketMatcher.pair(forBracketAt: 3, in: text), .init(open: 3, close: 5))
        XCTAssertEqual(BracketMatcher.pair(forBracketAt: 12, in: text), .init(open: 12, close: 14))
    }

    func testPrefersCharacterBeforeCaret() {
        let text = "(a)(b)" as NSString
        XCTAssertEqual(BracketMatcher.pair(adjacentTo: 3, in: text), .init(open: 0, close: 2))
        XCTAssertEqual(BracketMatcher.pair(adjacentTo: 0, in: text), .init(open: 0, close: 2))
        XCTAssertNil(BracketMatcher.pair(adjacentTo: 2, in: "(a" as NSString))
        XCTAssertNil(BracketMatcher.pair(adjacentTo: 1, in: "abc" as NSString))
    }

    func testUnbalancedReturnsNil() {
        XCTAssertNil(BracketMatcher.pair(forBracketAt: 0, in: "((a)" as NSString))
        XCTAssertNil(BracketMatcher.pair(forBracketAt: 2, in: "a))" as NSString))
    }

    func testRespectsScanLimit() {
        let text = ("(" + String(repeating: "x", count: 100) + ")") as NSString
        XCTAssertNil(BracketMatcher.pair(forBracketAt: 0, in: text, limit: 50))
        XCTAssertNotNil(BracketMatcher.pair(forBracketAt: 0, in: text, limit: 200))
    }
}
