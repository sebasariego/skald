import Foundation
@testable import Skald

/// A stand-in parser: every word in `keywords` is a "keyword", every digit run a "number".
/// Records the edits it was given so tests can check incremental plumbing.
final class FakeSyntaxParser: SyntaxParser, @unchecked Sendable {
    let keywords: Set<String>
    private(set) var parseCount = 0
    /// nil entries record full reparses.
    private(set) var receivedEdits: [[TextEdit]?] = []
    private let lock = NSLock()

    init(keywords: Set<String>) {
        self.keywords = keywords
    }

    func parse(_ text: TextSnapshot, edits: [TextEdit]?) async -> any SyntaxTree {
        lock.withLock {
            parseCount += 1
            receivedEdits.append(edits)
        }
        return FakeSyntaxTree(keywords: keywords, text: text)
    }
}

struct FakeSyntaxTree: SyntaxTree {
    let keywords: Set<String>
    let text: TextSnapshot

    func highlights(in range: NSRange, text _: TextSnapshot) -> [HighlightSpan] {
        let string = text.string
        let regex = try? NSRegularExpression(pattern: "[A-Za-z_]+|[0-9]+")
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: string.length))
        return (regex?.matches(in: string as String, range: clamped) ?? []).compactMap { match in
            let word = string.substring(with: match.range)
            if keywords.contains(word) { return HighlightSpan(range: match.range, capture: "keyword") }
            if word.first?.isNumber == true { return HighlightSpan(range: match.range, capture: "number") }
            return nil
        }
    }
}
