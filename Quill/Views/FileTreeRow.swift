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

    private var label: some View {
        HStack(spacing: 6) {
            Image(nsImage: FileIconProvider.icon(for: node.url))
                .resizable()
                .frame(width: 16, height: 16)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
