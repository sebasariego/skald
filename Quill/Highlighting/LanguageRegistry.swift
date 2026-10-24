import Foundation

/// The table of known languages, and the single hook that turns a definition into a
/// parser. The tree-sitter adapter installs that hook at launch; without it, files
/// open as plain text.
enum LanguageRegistry {
    static let all: [LanguageDefinition] = [
        LanguageDefinition(id: "swift", displayName: "Swift", fileExtensions: ["swift"], lineComment: "//"),
        LanguageDefinition(id: "python", displayName: "Python", fileExtensions: ["py", "pyi"], lineComment: "#"),
        LanguageDefinition(id: "json", displayName: "JSON", fileExtensions: ["json", "jsonc"], lineComment: nil),
        LanguageDefinition(id: "markdown", displayName: "Markdown", fileExtensions: ["md", "markdown"], lineComment: nil),
        // Injection-only: Markdown paragraphs hand their text to this grammar. No file extension.
        LanguageDefinition(id: "markdown_inline", displayName: "Markdown", fileExtensions: [], lineComment: nil),
        LanguageDefinition(id: "yaml", displayName: "YAML", fileExtensions: ["yml", "yaml"], lineComment: "#"),
    ]

    /// Creates a parser for a language, or returns nil when none is available.
    nonisolated(unsafe) static var parserFactory: (@Sendable (LanguageDefinition) -> (any SyntaxParser)?)?

    static func language(withID id: String) -> LanguageDefinition? {
        all.first { $0.id == id }
    }

    static func language(for url: URL) -> LanguageDefinition? {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        return all.first { $0.fileNames.contains(name) } ?? all.first { $0.fileExtensions.contains(ext) }
    }

    static func makeParser(for language: LanguageDefinition) -> (any SyntaxParser)? {
        parserFactory?(language)
    }
}
