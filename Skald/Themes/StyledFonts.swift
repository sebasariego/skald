import AppKit

/// A base editor font with its bold, italic and bold-italic faces, resolved once.
struct StyledFonts {
    let base: NSFont
    let bold: NSFont
    let italic: NSFont
    let boldItalic: NSFont

    init(base: NSFont) {
        self.base = base
        bold = Self.variant(of: base, traits: .boldFontMask)
        italic = Self.variant(of: base, traits: .italicFontMask)
        boldItalic = Self.variant(of: base, traits: [.boldFontMask, .italicFontMask])
    }

    func font(bold: Bool, italic: Bool) -> NSFont {
        switch (bold, italic) {
        case (true, true): return boldItalic
        case (true, false): return self.bold
        case (false, true): return self.italic
        case (false, false): return base
        }
    }

    /// Asks the font manager first; if the family has no such face, synthesizes one via
    /// descriptor traits so monospaced fonts still get an oblique.
    private static func variant(of font: NSFont, traits: NSFontTraitMask) -> NSFont {
        let converted = NSFontManager.shared.convert(font, toHaveTrait: traits)
        if converted != font { return converted }
        var symbolic = font.fontDescriptor.symbolicTraits
        if traits.contains(.boldFontMask) { symbolic.insert(.bold) }
        if traits.contains(.italicFontMask) { symbolic.insert(.italic) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(symbolic)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}
