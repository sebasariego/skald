import AppKit

/// Everything the editor surface needs to know about how to draw and edit text.
/// Persisted settings (step 6) produce one of these; views only read it.
struct EditorConfiguration: Equatable, Codable {
    var fontName: String? = nil
    var fontSize: CGFloat = 13
    var tabWidth: Int = 4
    var insertSpaces: Bool = true
    var softWrap: Bool = true
    var showLineNumbers: Bool = true
    var highlightCurrentLine: Bool = true
    var trimTrailingWhitespaceOnSave: Bool = false
    /// 1 is a solid editor; lower values let the blurred desktop show through.
    var backgroundOpacity: Double = 1.0

    static let minimumFontSize: CGFloat = 8
    static let maximumFontSize: CGFloat = 48
    static let minimumBackgroundOpacity: Double = 0.3

    var clampedBackgroundOpacity: Double {
        min(1, max(Self.minimumBackgroundOpacity, backgroundOpacity))
    }

    var isTranslucent: Bool { clampedBackgroundOpacity < 0.999 }

    var font: NSFont {
        if let fontName, let named = NSFont(name: fontName, size: fontSize) {
            return named
        }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// Tab stops every `tabWidth` spaces, measured in the current font.
    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        style.tabStops = []
        style.defaultTabInterval = spaceWidth * CGFloat(max(1, tabWidth))
        style.lineBreakMode = .byWordWrapping
        return style
    }

    /// Attributes every character in a document carries. Colors come from the theme later.
    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .paragraphStyle: paragraphStyle, .foregroundColor: NSColor.labelColor]
    }

    mutating func adjustFontSize(by delta: CGFloat) {
        fontSize = min(Self.maximumFontSize, max(Self.minimumFontSize, fontSize + delta))
    }
}
