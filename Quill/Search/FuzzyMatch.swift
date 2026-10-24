import Foundation

/// Result of a fuzzy match: a comparable score and the matched UTF-16 offsets in the candidate.
struct FuzzyMatch: Equatable, Sendable {
    var score: Int
    var positions: [Int]
}
