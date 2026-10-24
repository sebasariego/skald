import AppKit

/// How one kind of token is drawn.
struct TokenStyle: Equatable {
    var foreground: NSColor?
    var bold = false
    var italic = false
    var underline = false

    /// Parses a VS Code `fontStyle` string such as "bold italic".
    init(foreground: NSColor?, fontStyle: String? = nil) {
        self.foreground = foreground
        let words = Set((fontStyle ?? "").split(separator: " ").map(String.init))
        bold = words.contains("bold")
        italic = words.contains("italic")
        underline = words.contains("underline")
    }
}
