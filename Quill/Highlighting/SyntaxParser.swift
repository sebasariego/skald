import Foundation

/// Produces syntax trees for one language. Implementations run off the main actor and
/// keep whatever state they need for incremental reparsing between calls.
protocol SyntaxParser: Sendable {
    /// Parses `text`. `edits` lists the changes since the previous call, in order.
    /// Pass nil when the text was replaced wholesale, so no old tree is reused.
    func parse(_ text: TextSnapshot, edits: [TextEdit]?) async -> any SyntaxTree
}

/// A finished parse that the main actor can query cheaply for one screen at a time.
protocol SyntaxTree: Sendable {
    /// Highlight spans overlapping `range`, in document order.
    func highlights(in range: NSRange, text: TextSnapshot) -> [HighlightSpan]
}
