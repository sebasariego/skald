import SwiftUI

struct SidebarView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        if let root = workspace.folderTree.root {
            List(selection: selection) {
                Section(root.name) {
                    if let children = root.children {
                        ForEach(children) { child in
                            FileTreeRow(node: child)
                        }
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .listStyle(.sidebar)
        } else {
            ContentUnavailableView {
                Label("No Folder Open", systemImage: "folder")
            } description: {
                Text("Open a folder to browse its files.")
            } actions: {
                Button("Open Folder\u{2026}") { workspace.openFolderPanel() }
            }
        }
    }

    /// Selecting a file row opens it; the highlighted row follows the selected tab.
    private var selection: Binding<URL?> {
        Binding(
            get: { workspace.selectedDocument?.url },
            set: { url in
                guard let url else { return }
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return }
                Task { await workspace.open(fileAt: url) }
            }
        )
    }
}
