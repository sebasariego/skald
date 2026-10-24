import Foundation

/// A zero-based (row, column) position. Columns count UTF-16 units.
struct TextPoint: Equatable, Sendable {
    var row: Int
    var column: Int
}
