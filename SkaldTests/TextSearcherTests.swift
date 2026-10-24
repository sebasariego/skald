import XCTest
@testable import Skald

final class TextSearcherTests: XCTestCase {
    func testLiteralSearchIsCaseInsensitiveByDefault() async throws {
        let text = TextSnapshot("Foo foo FOO fo")
        let matches = try await TextSearcher.matches(for: SearchQuery(text: "foo"), in: text)
        XCTAssertEqual(matches, [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3), NSRange(location: 8, length: 3)])
        let sensitive = try await TextSearcher.matches(for: SearchQuery(text: "foo", isCaseSensitive: true), in: text)
        XCTAssertEqual(sensitive, [NSRange(location: 4, length: 3)])
    }

    func testLiteralSearchEscapesRegexCharacters() async throws {
        let text = TextSnapshot("a.b a?b axb")
        let matches = try await TextSearcher.matches(for: SearchQuery(text: "a.b"), in: text)
        XCTAssertEqual(matches, [NSRange(location: 0, length: 3)])
    }

    func testRegexSearchAnchorsPerLine() async throws {
        let text = TextSnapshot("one\ntwo\nthree")
        let matches = try await TextSearcher.matches(for: SearchQuery(text: "^t\\w+", isRegex: true), in: text)
        XCTAssertEqual(matches, [NSRange(location: 4, length: 3), NSRange(location: 8, length: 5)])
    }

    func testInvalidRegexThrows() async {
        do {
            _ = try await TextSearcher.matches(for: SearchQuery(text: "(", isRegex: true), in: TextSnapshot("x"))
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is TextSearchError)
        }
    }

    func testEmptyQueryHasNoMatches() async throws {
        let matches = try await TextSearcher.matches(for: SearchQuery(text: ""), in: TextSnapshot("abc"))
        XCTAssertTrue(matches.isEmpty)
    }

    func testRegexReplacementExpandsGroups() {
        let text = TextSnapshot("name: Ada")
        let query = SearchQuery(text: "(\\w+): (\\w+)", isRegex: true)
        let replacement = TextSearcher.replacement(for: NSRange(location: 0, length: 9), query: query, template: "$2 = $1", in: text)
        XCTAssertEqual(replacement, "Ada = name")
        let literal = TextSearcher.replacement(for: NSRange(location: 0, length: 4), query: SearchQuery(text: "name"), template: "$1", in: text)
        XCTAssertEqual(literal, "$1")
    }

    func testIndexOfMatchWraps() {
        let matches = [NSRange(location: 2, length: 1), NSRange(location: 10, length: 1), NSRange(location: 20, length: 1)]
        XCTAssertEqual(TextSearcher.indexOfMatch(atOrAfter: 0, in: matches), 0)
        XCTAssertEqual(TextSearcher.indexOfMatch(atOrAfter: 3, in: matches), 1)
        XCTAssertEqual(TextSearcher.indexOfMatch(atOrAfter: 10, in: matches), 1)
        XCTAssertEqual(TextSearcher.indexOfMatch(atOrAfter: 21, in: matches), 0)
        XCTAssertNil(TextSearcher.indexOfMatch(atOrAfter: 0, in: []))
    }

    func testLargeFileSearchIsFast() async throws {
        let line = "let value = compute(input) // trailing comment\n"
        let text = TextSnapshot(String(repeating: line, count: 100_000)) // ~4.7 MB
        let start = Date()
        let matches = try await TextSearcher.matches(for: SearchQuery(text: "compute"), in: text)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(matches.count, 100_000)
        XCTAssertLessThan(elapsed, 2.0, "literal search over ~5 MB took \(elapsed)s")
    }
}
