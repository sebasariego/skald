import Foundation

/// Static facts about a language. Adding a language is one entry in `LanguageRegistry`.
struct LanguageDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let fileExtensions: [String]
    let fileNames: [String]
    let lineComment: String?

    init(id: String, displayName: String, fileExtensions: [String], fileNames: [String] = [], lineComment: String?) {
        self.id = id
        self.displayName = displayName
        self.fileExtensions = fileExtensions
        self.fileNames = fileNames
        self.lineComment = lineComment
    }

    /// Resource name of the tree-sitter highlight query, e.g. "swift.highlights" (.scm).
    var highlightsQueryResource: String { "\(id).highlights" }
}
