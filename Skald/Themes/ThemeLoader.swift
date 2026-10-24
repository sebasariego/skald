import Foundation

enum ThemeError: LocalizedError {
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .malformed(let detail): return "The theme file is malformed: \(detail)"
        }
    }
}

/// Reads VS Code-style JSON color themes.
enum ThemeLoader {
    private struct File: Decodable {
        var name: String?
        var type: String?
        var colors: [String: String]?
        var tokenColors: [Token]?

        struct Token: Decodable {
            var name: String?
            var scope: Scope?
            var settings: Settings

            struct Settings: Decodable {
                var foreground: String?
                var fontStyle: String?
            }
        }

        /// `scope` may be a single string, a comma-separated string, or an array.
        enum Scope: Decodable {
            case one(String)
            case many([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let one = try? container.decode(String.self) {
                    self = .one(one)
                } else {
                    self = .many(try container.decode([String].self))
                }
            }

            var values: [String] {
                switch self {
                case .one(let value): return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                case .many(let values): return values
                }
            }
        }
    }

    static func load(from url: URL) throws -> Theme {
        let data = try Data(contentsOf: url)
        return try load(data: data, fallbackName: url.deletingPathExtension().lastPathComponent)
    }

    static func load(data: Data, fallbackName: String) throws -> Theme {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch {
            throw ThemeError.malformed(error.localizedDescription)
        }
        let isDark = (file.type ?? "dark").lowercased() != "light"
        let rules = (file.tokenColors ?? []).compactMap { token -> TokenColorRule? in
            let scopes = token.scope?.values.filter { !$0.isEmpty } ?? []
            guard !scopes.isEmpty else { return nil }
            let foreground = token.settings.foreground.flatMap(HexColor.color(from:))
            guard foreground != nil || token.settings.fontStyle != nil else { return nil }
            return TokenColorRule(scopes: scopes, style: TokenStyle(foreground: foreground, fontStyle: token.settings.fontStyle))
        }
        return Theme(
            name: file.name ?? fallbackName,
            isDark: isDark,
            colors: ThemeColors(table: file.colors ?? [:], isDark: isDark),
            tokenRules: rules
        )
    }

    /// Used before any theme file has loaded, and when none can be found.
    static let fallbackTheme = Theme(
        name: "System",
        isDark: true,
        colors: ThemeColors(table: [:], isDark: true),
        tokenRules: []
    )

    /// Every theme bundled with the app, sorted by name.
    static func bundledThemes(in bundle: Bundle = .main) -> [Theme] {
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return urls
            .filter { $0.lastPathComponent.hasSuffix(".theme.json") }
            .compactMap { try? load(from: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
