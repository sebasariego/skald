import AppKit

/// A loaded color theme in VS Code's shape: chrome colors plus scope-based token rules.
struct Theme: Equatable, Identifiable {
    var id: String { name }
    var name: String
    var isDark: Bool
    var colors: ThemeColors
    var tokenRules: [TokenColorRule]

    var appearance: NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}
