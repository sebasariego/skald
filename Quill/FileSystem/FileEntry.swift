import Foundation

/// One file inside the open folder, prepared for fuzzy matching.
struct FileEntry: Identifiable, Equatable, Sendable {
    let url: URL
    let relativePath: String
    let searchBuffer: [UInt16]
    let originalBuffer: [UInt16]

    var id: URL { url }
    var fileName: String { url.lastPathComponent }
    var directory: String {
        let path = (relativePath as NSString).deletingLastPathComponent
        return path.isEmpty ? "" : path
    }

    init(url: URL, relativePath: String) {
        self.url = url
        self.relativePath = relativePath
        self.searchBuffer = FuzzyMatcher.lowercasedUTF16(relativePath)
        self.originalBuffer = Array(relativePath.utf16)
    }
}
