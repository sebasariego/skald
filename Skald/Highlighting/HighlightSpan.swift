import Foundation

/// A range of text tagged with a highlight capture such as "keyword" or "string.escape".
struct HighlightSpan: Equatable, Sendable {
    var range: NSRange
    var capture: String
}
