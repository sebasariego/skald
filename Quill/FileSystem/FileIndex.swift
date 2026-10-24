import Foundation
import Observation

/// Every file under the open folder, for quick open. Built off the main actor.
@MainActor
@Observable
final class FileIndex {
    private(set) var entries: [FileEntry] = []
    private(set) var isIndexing = false
    private(set) var rootURL: URL?
    @ObservationIgnored private var indexTask: Task<Void, Never>?

    nonisolated static let ignoredDirectoryNames: Set<String> = [
        "node_modules", "DerivedData", ".build", "build", "Pods", "dist", "target", ".git", ".svn", ".hg",
    ]
    nonisolated static let maximumEntries = 100_000

    func setRoot(_ url: URL?) {
        rootURL = url
        entries = []
        refresh()
    }

    func refresh() {
        indexTask?.cancel()
        guard let rootURL else {
            isIndexing = false
            return
        }
        isIndexing = true
        indexTask = Task { [weak self] in
            let found = await Self.scan(rootURL)
            guard !Task.isCancelled, let self, self.rootURL == rootURL else { return }
            self.entries = found
            self.isIndexing = false
        }
    }

    nonisolated static func scan(_ root: URL) async -> [FileEntry] {
        scanSynchronously(root)
    }

    nonisolated private static func scanSynchronously(_ root: URL) -> [FileEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let rootPath = root.standardizedFileURL.path
        var results: [FileEntry] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { return [] }
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                if ignoredDirectoryNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            let relative = path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : url.lastPathComponent
            results.append(FileEntry(url: url, relativePath: relative))
            if results.count >= maximumEntries { break }
        }
        results.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return results
    }
}
