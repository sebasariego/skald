import Foundation

/// One replacement, described in the shape incremental parsers want: UTF-16 offsets
/// and (row, column) points for the start, the old end and the new end.
struct TextEdit: Equatable, Sendable {
    var startOffset: Int
    var oldEndOffset: Int
    var newEndOffset: Int
    var startPoint: TextPoint
    var oldEndPoint: TextPoint
    var newEndPoint: TextPoint

    var oldRange: NSRange { NSRange(location: startOffset, length: oldEndOffset - startOffset) }
    var newRange: NSRange { NSRange(location: startOffset, length: newEndOffset - startOffset) }
}
