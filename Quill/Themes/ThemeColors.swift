import AppKit

/// Editor chrome colors, resolved from a theme's `colors` table with sensible fallbacks.
struct ThemeColors: Equatable {
    var editorBackground: NSColor
    var editorForeground: NSColor
    var lineNumber: NSColor
    var lineNumberActive: NSColor
    var currentLineBackground: NSColor
    var selectionBackground: NSColor
    var cursor: NSColor
    var bracketMatchBackground: NSColor
    var findMatchBackground: NSColor
    var findMatchHighlightBackground: NSColor

    init(table: [String: String], isDark: Bool) {
        func color(_ key: String, _ fallback: NSColor) -> NSColor {
            table[key].flatMap(HexColor.color(from:)) ?? fallback
        }
        let background = color("editor.background", isDark ? NSColor(white: 0.12, alpha: 1) : .white)
        let foreground = color("editor.foreground", isDark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.15, alpha: 1))
        editorBackground = background
        editorForeground = foreground
        lineNumber = color("editorLineNumber.foreground", foreground.withAlphaComponent(0.4))
        lineNumberActive = color("editorLineNumber.activeForeground", foreground)
        currentLineBackground = color("editor.lineHighlightBackground", foreground.withAlphaComponent(0.06))
        selectionBackground = color("editor.selectionBackground", NSColor.selectedTextBackgroundColor)
        cursor = color("editorCursor.foreground", foreground)
        bracketMatchBackground = color("editorBracketMatch.background", foreground.withAlphaComponent(0.2))
        findMatchBackground = color("editor.findMatchBackground", NSColor(srgbRed: 0.98, green: 0.62, blue: 0.2, alpha: 0.7))
        findMatchHighlightBackground = color("editor.findMatchHighlightBackground", NSColor(srgbRed: 0.98, green: 0.82, blue: 0.3, alpha: 0.35))
    }
}
