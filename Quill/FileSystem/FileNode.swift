import Foundation
import Observation

/// One row of the sidebar tree. Children load lazily the first time a folder expands.
@MainActor
@Observable
final class FileNode: Identifiable {
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?
    var isExpanded = false
    var isLoading = false

    nonisolated var id: URL { url }

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
    }
}
