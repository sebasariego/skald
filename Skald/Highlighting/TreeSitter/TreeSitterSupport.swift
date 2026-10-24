import Foundation
import OSLog
import TreeSitter
import TreeSitterGrammars

/// Wires the compiled grammars into `LanguageRegistry`. Adding a language means one
/// line in `grammarFunctions`, one entry in the registry, and a highlights query file.
enum TreeSitterSupport {
    private static let logger = Logger(subsystem: "dev.local.skald", category: "tree-sitter")

    /// Language id to the generated grammar entry point.
    nonisolated(unsafe) private static let grammarFunctions: [String: () -> OpaquePointer?] = [
        "swift": { tree_sitter_swift() },
        "python": { tree_sitter_python() },
        "json": { tree_sitter_json() },
        "markdown": { tree_sitter_markdown() },
        "markdown_inline": { tree_sitter_markdown_inline() },
        "yaml": { tree_sitter_yaml() },
        "bash": { tree_sitter_bash() },
        "html": { tree_sitter_html() },
        "css": { tree_sitter_css() },
        "xml": { tree_sitter_xml() },
        "javascript": { tree_sitter_javascript() },
        "typescript": { tree_sitter_typescript() },
        "tsx": { tree_sitter_tsx() },
    ]

    /// Names used by injection queries and fence info strings that differ from our language ids.
    private static let injectionAliases: [String: String] = [
        "md": "markdown", "py": "python", "yml": "yaml",
        "sh": "bash", "shell": "bash", "zsh": "bash", "console": "bash",
        "js": "javascript", "jsx": "javascript", "mjs": "javascript", "node": "javascript",
        "ts": "typescript", "svg": "xml", "xhtml": "html", "htm": "html",
    ]

    /// Compiled queries are shared by every document in the same language.
    private static let queryCache = QueryCache()

    /// Installs the parser factory. `queryDirectory` overrides the app bundle (tests).
    static func install(queryDirectory: URL? = nil) {
        LanguageRegistry.parserFactory = { language in
            makeParser(for: language, queryDirectory: queryDirectory)
        }
    }

    static func language(withID id: String) -> OpaquePointer? {
        grammarFunctions[id]?()
    }

    static func makeParser(for language: LanguageDefinition, queryDirectory: URL? = nil) -> (any SyntaxParser)? {
        guard let grammar = self.language(withID: language.id) else { return nil }
        guard let query = queryCache.query(for: language, grammar: grammar, directory: queryDirectory, kind: .highlights) else { return nil }
        let injections = queryCache.query(for: language, grammar: grammar, directory: queryDirectory, kind: .injections)
        return TreeSitterParser(language: grammar, query: query, injections: injections) { name in
            injectedLanguage(named: name, queryDirectory: queryDirectory)
        }
    }

    /// Resolves an injection language name ("swift", "markdown_inline") to a grammar and query.
    static func injectedLanguage(named name: String, queryDirectory: URL?) -> InjectedLanguage? {
        let id = injectionAliases[name] ?? name
        guard let definition = LanguageRegistry.language(withID: id), let grammar = language(withID: id),
              let query = queryCache.query(for: definition, grammar: grammar, directory: queryDirectory, kind: .highlights) else { return nil }
        return InjectedLanguage(language: grammar, query: query)
    }

    enum QueryKind: String {
        case highlights
        case injections
    }

    static func querySource(for language: LanguageDefinition, directory: URL?, kind: QueryKind = .highlights) -> String? {
        let resource = "\(language.id).\(kind.rawValue)"
        let url: URL?
        if let directory {
            url = directory.appendingPathComponent("\(resource).scm")
        } else {
            url = Bundle.main.url(forResource: resource, withExtension: "scm")
        }
        guard let url, let source = try? String(contentsOf: url, encoding: .utf8) else {
            if kind == .highlights { logger.error("No highlight query for \(language.id, privacy: .public)") }
            return nil
        }
        return source
    }

    private final class QueryCache: @unchecked Sendable {
        private var queries: [String: TreeSitterQuery] = [:]
        private var failed: Set<String> = []
        private let lock = NSLock()

        func query(for language: LanguageDefinition, grammar: OpaquePointer, directory: URL?, kind: QueryKind) -> TreeSitterQuery? {
            let key = "\(language.id).\(kind.rawValue)"
            lock.lock()
            defer { lock.unlock() }
            if let cached = queries[key] { return cached }
            if failed.contains(key) { return nil }
            guard let source = TreeSitterSupport.querySource(for: language, directory: directory, kind: kind) else {
                failed.insert(key)
                return nil
            }
            do {
                let query = try TreeSitterQuery(language: grammar, source: source)
                queries[key] = query
                return query
            } catch {
                TreeSitterSupport.logger.error("\(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
                failed.insert(key)
                return nil
            }
        }
    }
}
