import Foundation

/// Indentation rules: keep the previous line's leading whitespace, add one level
/// after an opening bracket, and split a bracket pair onto three lines.
struct AutoIndenter {
    var tabWidth: Int
    var insertSpaces: Bool

    init(tabWidth: Int, insertSpaces: Bool) {
        self.tabWidth = max(1, tabWidth)
        self.insertSpaces = insertSpaces
    }

    init(_ configuration: EditorConfiguration) {
        self.init(tabWidth: configuration.tabWidth, insertSpaces: configuration.insertSpaces)
    }

    var indentUnit: String {
        insertSpaces ? String(repeating: " ", count: tabWidth) : "\t"
    }

    struct Insertion: Equatable {
        let text: String
        let caretOffset: Int
    }

    /// What pressing Return at `location` should insert.
    func newline(at location: Int, in text: NSString) -> Insertion {
        let lineStart = startOfLine(containing: location, in: text)
        let indent = leadingWhitespace(from: lineStart, upTo: location, in: text)
        let before: unichar? = location > 0 ? text.character(at: location - 1) : nil
        let after: unichar? = location < text.length ? text.character(at: location) : nil

        guard let before, Self.openers.contains(before) else {
            return Insertion(text: "\n" + indent, caretOffset: 1 + indent.utf16.count)
        }
        let inner = "\n" + indent + indentUnit
        if let after, Self.closer(for: before) == after {
            return Insertion(text: inner + "\n" + indent, caretOffset: inner.utf16.count)
        }
        return Insertion(text: inner, caretOffset: inner.utf16.count)
    }

    /// Spaces (or a tab) that move from `column` to the next tab stop.
    func tabInsertion(atColumn column: Int) -> String {
        guard insertSpaces else { return "\t" }
        let toNextStop = tabWidth - (column % tabWidth)
        return String(repeating: " ", count: toNextStop)
    }

    /// Visual column of `location`, expanding tabs to the next stop.
    func column(of location: Int, in text: NSString) -> Int {
        let lineStart = startOfLine(containing: location, in: text)
        var column = 0
        for index in lineStart..<location {
            if text.character(at: index) == 0x09 {
                column += tabWidth - (column % tabWidth)
            } else {
                column += 1
            }
        }
        return column
    }

    /// Adds one indent level to every line in `text` that is not blank.
    func indented(_ text: String) -> String {
        rewriteLines(in: text) { line in line.isEmpty ? line : indentUnit + line }
    }

    /// Removes up to one indent level (tab or `tabWidth` spaces) from every line.
    func outdented(_ text: String) -> String {
        rewriteLines(in: text) { line in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            var count = 0
            for character in line where character == " " {
                count += 1
                if count == tabWidth { break }
            }
            return String(line.dropFirst(count))
        }
    }

    // MARK: Helpers

    private static let openers: Set<unichar> = [0x28, 0x5B, 0x7B]

    private static func closer(for opener: unichar) -> unichar {
        switch opener {
        case 0x28: return 0x29
        case 0x5B: return 0x5D
        default: return 0x7D
        }
    }

    func startOfLine(containing location: Int, in text: NSString) -> Int {
        var index = min(location, text.length)
        while index > 0, text.character(at: index - 1) != 0x0A {
            index -= 1
        }
        return index
    }

    private func leadingWhitespace(from start: Int, upTo end: Int, in text: NSString) -> String {
        var index = start
        while index < end {
            let character = text.character(at: index)
            guard character == 0x20 || character == 0x09 else { break }
            index += 1
        }
        return text.substring(with: NSRange(location: start, length: index - start))
    }

    private func rewriteLines(in text: String, _ transform: (String) -> String) -> String {
        let hasTrailingNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if hasTrailingNewline { lines.removeLast() }
        var result = lines.map(transform).joined(separator: "\n")
        if hasTrailingNewline { result += "\n" }
        return result
    }
}
