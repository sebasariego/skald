import XCTest
@testable import Skald

final class FuzzyMatcherTests: XCTestCase {
    private func score(_ pattern: String, _ candidate: String) -> Int? {
        FuzzyMatcher.match(pattern, in: candidate)?.score
    }

    func testRequiresSubsequence() {
        XCTAssertNotNil(FuzzyMatcher.match("dcs", in: "Document/Store.swift"))
        XCTAssertNil(FuzzyMatcher.match("xyz", in: "Document.swift"))
        XCTAssertNil(FuzzyMatcher.match("toolong", in: "short"))
        XCTAssertEqual(FuzzyMatcher.match("", in: "anything"), FuzzyMatch(score: 0, positions: []))
    }

    func testIsCaseInsensitive() {
        XCTAssertEqual(FuzzyMatcher.match("DOC", in: "document.swift")?.positions, [0, 1, 2])
    }

    func testPositionsAreAscendingAndPointAtMatchingCharacters() throws {
        let candidate = "Sources/Editor/CodeTextView.swift"
        let match = try XCTUnwrap(FuzzyMatcher.match("ctv", in: candidate))
        let units = Array(candidate.lowercased().utf16)
        XCTAssertEqual(match.positions.map { Character(UnicodeScalar(units[$0]) ?? " ") }, ["c", "t", "v"])
        XCTAssertEqual(match.positions, match.positions.sorted())
    }

    func testPrefersWordStartsAndCamelHumps() throws {
        let humps = try XCTUnwrap(score("ctv", "CodeTextView.swift"))
        let scattered = try XCTUnwrap(score("ctv", "actvsomething.swift"))
        XCTAssertGreaterThan(humps, scattered)
        let match = try XCTUnwrap(FuzzyMatcher.match("ctv", in: "CodeTextView.swift"))
        XCTAssertEqual(match.positions, [0, 4, 8])
    }

    func testPrefersConsecutiveRuns() throws {
        XCTAssertGreaterThan(try XCTUnwrap(score("store", "DocumentStore.swift")), try XCTUnwrap(score("store", "s_t_o_r_e.swift")))
    }

    func testPrefersShorterCandidatesOnTies() throws {
        XCTAssertGreaterThan(try XCTUnwrap(score("doc", "Document.swift")), try XCTUnwrap(score("doc", "DocumentStoreTests.swift")))
    }

    func testPathSeparatorsCountAsBoundaries() throws {
        let match = try XCTUnwrap(FuzzyMatcher.match("ev", in: "Skald/Editor/EditorView.swift"))
        XCTAssertEqual(match.positions, [13, 19])
    }

    func testManyCandidatesStayFast() {
        let candidates = (0..<20_000).map { "Sources/Module\($0 % 50)/Feature\($0)/SomeLongFileName\($0).swift" }
        let buffers = candidates.map { (FuzzyMatcher.lowercasedUTF16($0), Array($0.utf16)) }
        let pattern = FuzzyMatcher.lowercasedUTF16("slfn12")
        let start = Date()
        var count = 0
        for (lower, original) in buffers where FuzzyMatcher.match(pattern, in: lower, original: original) != nil {
            count += 1
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThan(count, 0)
        XCTAssertLessThan(elapsed, 1.5, "matching 20k paths took \(elapsed)s")
    }
}
