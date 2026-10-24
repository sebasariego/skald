import Foundation

/// Finds the partner of a bracket next to the caret by depth counting. Pure and
/// grammar-agnostic; tree-sitter can refine this later.
enum BracketMatcher {
    struct Pair: Equatable {
        let open: Int
        let close: Int
    }

    private static let closers: [unichar: unichar] = [
        0x28: 0x29, // ( )
        0x5B: 0x5D, // [ ]
        0x7B: 0x7D, // { }
    ]
    private static let openers: [unichar: unichar] = Dictionary(uniqueKeysWithValues: closers.map { ($1, $0) })

    /// Looks at the character before the caret, then the one after it.
    /// Scans at most `limit` characters so a 5 MB file never stalls the caret.
    static func pair(adjacentTo location: Int, in text: NSString, limit: Int = 250_000) -> Pair? {
        if location > 0, let pair = pair(forBracketAt: location - 1, in: text, limit: limit) {
            return pair
        }
        if location < text.length, let pair = pair(forBracketAt: location, in: text, limit: limit) {
            return pair
        }
        return nil
    }

    static func pair(forBracketAt index: Int, in text: NSString, limit: Int = 250_000) -> Pair? {
        guard index >= 0, index < text.length else { return nil }
        let character = text.character(at: index)
        if let closer = closers[character] {
            return scanForward(from: index, opener: character, closer: closer, in: text, limit: limit)
                .map { Pair(open: index, close: $0) }
        }
        if let opener = openers[character] {
            return scanBackward(from: index, opener: opener, closer: character, in: text, limit: limit)
                .map { Pair(open: $0, close: index) }
        }
        return nil
    }

    private static func scanForward(from start: Int, opener: unichar, closer: unichar, in text: NSString, limit: Int) -> Int? {
        var depth = 0
        let end = min(text.length, start + limit)
        for index in start..<end {
            let character = text.character(at: index)
            if character == opener { depth += 1 } else if character == closer {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func scanBackward(from start: Int, opener: unichar, closer: unichar, in text: NSString, limit: Int) -> Int? {
        var depth = 0
        let end = max(0, start - limit)
        var index = start
        while index >= end {
            let character = text.character(at: index)
            if character == closer { depth += 1 } else if character == opener {
                depth -= 1
                if depth == 0 { return index }
            }
            index -= 1
        }
        return nil
    }
}
