import Foundation
import Observation

/// The open folder and its lazily loaded tree.
@MainActor
@Observable
final class FolderTree {
    private(set) var root: FileNode?

    func open(_ url: URL) {
        let node = FileNode(url: url.standardizedFileURL, isDirectory: true)
        node.isExpanded = true
        root = node
        Task { await loadChildrenIfNeeded(node) }
    }

    func close() {
        root = nil
    }

    func loadChildrenIfNeeded(_ node: FileNode) async {
        guard node.isDirectory, node.children == nil, !node.isLoading else { return }
        node.isLoading = true
        defer { node.isLoading = false }
        let entries = await Self.listDirectory(node.url)
        node.children = entries.map { FileNode(url: $0.url, isDirectory: $0.isDirectory) }
    }

    /// Forgets loaded children so the next expansion re-reads the disk.
    func refresh(_ node: FileNode) async {
        node.children = nil
        await loadChildrenIfNeeded(node)
    }

    /// Lists visible children, folders first, then case-insensitive by name.
    nonisolated static func listDirectory(_ url: URL) async -> [DirectoryEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        let entries = contents.map { child -> DirectoryEntry in
            let values = try? child.resourceValues(forKeys: Set(keys))
            return DirectoryEntry(url: child, isDirectory: values?.isDirectory ?? false)
        }
        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }
    }
}
