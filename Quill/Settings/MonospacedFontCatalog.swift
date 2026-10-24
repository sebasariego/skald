import AppKit

/// Fixed-pitch font families installed on this Mac, for the font picker.
enum MonospacedFontCatalog {
    static let systemOption = "System Monospaced"

    static func familyNames() -> [String] {
        let manager = NSFontManager.shared
        let families = manager.availableFontFamilies.filter { family in
            guard let postScriptName = memberNames(ofFamily: family).first,
                  let font = NSFont(name: postScriptName, size: 12) else { return false }
            return font.isFixedPitch
        }
        return families.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Every installed family, for people who want a proportional font in the editor.
    static func allFamilyNames() -> [String] {
        NSFontManager.shared.availableFontFamilies.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Regular-weight member of a family, or nil for the system option.
    static func fontName(forFamily family: String) -> String? {
        guard family != systemOption else { return nil }
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        // Each member is [postScriptName, styleName, weight, traits]; weight 5 is regular.
        let regular = members.first { member in
            member.count > 2 && (member[2] as? Int) == 5
        } ?? members.first
        return regular?.first as? String
    }

    private static func memberNames(ofFamily family: String) -> [String] {
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        return members.compactMap { $0.first as? String }
    }

    /// Family for a stored PostScript name, falling back to the system option.
    static func family(forFontName fontName: String?) -> String {
        guard let fontName, let font = NSFont(name: fontName, size: 12), let family = font.familyName else {
            return systemOption
        }
        return family
    }
}
