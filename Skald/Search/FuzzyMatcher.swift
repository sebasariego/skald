import Foundation

/// Subsequence matching with a score that prefers matches at word starts, consecutive
/// runs, and shorter candidates. Works on lowercased UTF-16 so callers can precompute
/// candidate buffers once and match thousands of them per keystroke.
///
/// Scoring follows the shape of fzf and VS Code: every matched character earns a base
/// score, boundaries and camelCase humps add a bonus, gaps cost, and a match that is
/// neither at a boundary nor glued to the previous match is penalized as a mid-word jump.
enum FuzzyMatcher {
    static let matchScore = 16
    static let boundaryBonus = 10
    static let camelBonus = 9
    static let consecutiveBonus = 8
    static let firstCharacterMultiplier = 2
    static let gapStartPenalty = 6
    static let gapExtendPenalty = 1
    static let midWordJumpPenalty = 10

    static func lowercasedUTF16(_ text: String) -> [UInt16] {
        Array(text.lowercased().utf16)
    }

    static func match(_ pattern: String, in candidate: String) -> FuzzyMatch? {
        match(lowercasedUTF16(pattern), in: lowercasedUTF16(candidate), original: Array(candidate.utf16))
    }

    /// `original` keeps the candidate's case so camelCase humps can earn a bonus.
    static func match(_ pattern: [UInt16], in candidate: [UInt16], original: [UInt16]? = nil) -> FuzzyMatch? {
        let n = pattern.count
        let m = candidate.count
        if n == 0 { return FuzzyMatch(score: 0, positions: []) }
        if n > m { return nil }
        guard isSubsequence(pattern, of: candidate) else { return nil }

        let bonuses = positionBonuses(candidate, original: original ?? candidate)
        let none = Int.min / 4

        // previous[j]: best score with pattern[i-1] matched exactly at candidate[j].
        var previous = [Int](repeating: none, count: m)
        var parents = [[Int]](repeating: [Int](repeating: -1, count: m), count: n)

        for j in 0..<m where candidate[j] == pattern[0] {
            var score = matchScore + bonuses[j] * (j == 0 ? firstCharacterMultiplier : 1)
            if bonuses[j] == 0 { score -= midWordJumpPenalty }
            previous[j] = score
        }

        for i in 1..<n {
            var current = [Int](repeating: none, count: m)
            // Best "previous match at k < j-1, then a gap up to j" score, maintained incrementally.
            var gapBest = none
            var gapIndex = -1
            for j in 1..<m {
                // A gap path to j can start from any k <= j-2; add k = j-2 now (gap length 1).
                if j >= 2 {
                    let k = j - 2
                    if gapBest != none { gapBest -= gapExtendPenalty }
                    if previous[k] != none {
                        let fresh = previous[k] - gapStartPenalty
                        if fresh > gapBest {
                            gapBest = fresh
                            gapIndex = k
                        }
                    }
                }
                guard candidate[j] == pattern[i] else { continue }
                var best = none
                var parent = -1
                if previous[j - 1] != none {
                    best = previous[j - 1] + consecutiveBonus
                    parent = j - 1
                }
                if gapBest != none {
                    var gapScore = gapBest
                    if bonuses[j] == 0 { gapScore -= midWordJumpPenalty }
                    if gapScore > best {
                        best = gapScore
                        parent = gapIndex
                    }
                }
                guard best != none else { continue }
                current[j] = best + matchScore + bonuses[j]
                parents[i][j] = parent
            }
            previous = current
        }

        var bestScore = none
        var bestEnd = -1
        for j in 0..<m where previous[j] > bestScore {
            bestScore = previous[j]
            bestEnd = j
        }
        guard bestEnd >= 0 else { return nil }

        var positions = [Int](repeating: 0, count: n)
        var j = bestEnd
        for i in stride(from: n - 1, through: 0, by: -1) {
            positions[i] = j
            if i > 0 { j = parents[i][j] }
        }
        // Shorter candidates win ties; unmatched tail characters cost a little.
        let lengthPenalty = (m - positions[n - 1] - 1) / 4 + m / 16
        return FuzzyMatch(score: bestScore - lengthPenalty, positions: positions)
    }

    private static func isSubsequence(_ pattern: [UInt16], of candidate: [UInt16]) -> Bool {
        var index = 0
        for unit in candidate where index < pattern.count {
            if unit == pattern[index] { index += 1 }
        }
        return index == pattern.count
    }

    /// Bonus for matching at each position: word starts after separators, camelCase humps.
    private static func positionBonuses(_ candidate: [UInt16], original: [UInt16]) -> [Int] {
        var bonuses = [Int](repeating: 0, count: candidate.count)
        for j in 0..<candidate.count {
            if j == 0 {
                bonuses[j] = boundaryBonus
                continue
            }
            if isSeparator(candidate[j - 1]) {
                bonuses[j] = boundaryBonus
            } else if j < original.count, isUppercase(original[j]), isLowercase(original[j - 1]) {
                bonuses[j] = camelBonus
            }
        }
        return bonuses
    }

    private static func isSeparator(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x2F, 0x5F, 0x2D, 0x2E, 0x20, 0x3A: return true // / _ - . space :
        default: return false
        }
    }

    private static func isUppercase(_ unit: UInt16) -> Bool { unit >= 0x41 && unit <= 0x5A }
    private static func isLowercase(_ unit: UInt16) -> Bool { unit >= 0x61 && unit <= 0x7A }
}
