import SwiftUI

/// Recursive sidebar row. Folders load their children on first expansion.
struct FileTreeRow: View {
    @Environment(Workspace.self) private var workspace
    @Bindable var node: FileNode

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $node.isExpanded) {
                if let children = node.children {
                    ForEach(children) { child in
                        FileTreeRow(node: child)
                    }
                } else if node.isLoading {
                    ProgressView().controlSize(.mini)
                }
            } label: {
                label
            }
            .onChange(of: node.isExpanded, initial: true) { _, expanded in
                guard expanded else { return }
                Task { await workspace.folderTree.loadChildrenIfNeeded(node) }
            }
        } else {
            label.tag(node.url)
        }
    }

    /// Folders get a full-brightness glyph and a slightly heavier name so they read at a
    /// glance; files keep thin grey glyphs. Monochrome throughout, no accent color.
    private var label: some View {
        HStack(spacing: 7) {
            if node.isDirectory {
                Image(systemName: node.isExpanded ? FileIconProvider.openFolderSymbol : FileIconProvider.folderSymbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 18, alignment: .center)
                Text(node.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Image(systemName: FileIconProvider.symbolName(for: node.url, isDirectory: false))
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .center)
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
