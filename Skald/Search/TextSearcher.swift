import Foundation

enum TextSearchError: LocalizedError {
    case invalidPattern

    var errorDescription: String? { "Invalid regular expression" }
}

/// Finds and replaces inside a text snapshot. No UI, no main-actor requirement.
enum TextSearcher {
    /// All match ranges in document order. Empty query means no matches.
    static func matches(for query: SearchQuery, in text: TextSnapshot) async throws -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let regex: NSRegularExpression
        do {
            regex = try query.makeRegex()
        } catch {
            throw TextSearchError.invalidPattern
        }
        let string = text.string as String
        let fullRange = NSRange(location: 0, length: text.length)
        var results: [NSRange] = []
        regex.enumerateMatches(in: string, options: [], range: fullRange) { result, _, _ in
            guard let result, result.range.length > 0 else { return }
            results.append(result.range)
        }
        return results
    }

    /// The text that replaces `match`, expanding `$1`-style groups in regex mode.
    static func replacement(for match: NSRange, query: SearchQuery, template: String, in text: TextSnapshot) -> String {
        guard query.isRegex, let regex = try? query.makeRegex() else { return template }
        let string = text.string as String
        guard let result = regex.firstMatch(in: string, options: [.anchored], range: match) else { return template }
        return regex.replacementString(for: result, in: string, offset: 0, template: template)
    }

    /// Index of the first match starting at or after `location`, wrapping to 0.
    static func indexOfMatch(atOrAfter location: Int, in matches: [NSRange]) -> Int? {
        guard !matches.isEmpty else { return nil }
        var low = 0
        var high = matches.count
        while low < high {
            let mid = (low + high) / 2
            if matches[mid].location < location { low = mid + 1 } else { high = mid }
        }
        return low < matches.count ? low : 0
    }
}
