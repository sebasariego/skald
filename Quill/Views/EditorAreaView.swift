import SwiftUI

struct EditorAreaView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        ZStack {
            if workspace.editorConfiguration.isTranslucent {
                VisualEffectBackground().ignoresSafeArea()
            }
            content
        }
        .navigationTitle(workspace.selectedDocument?.displayName ?? "Quill")
        .background(WindowStateView(representedURL: workspace.selectedDocument?.url, isEdited: workspace.selectedDocument?.isDirty ?? false))
    }

    private var content: some View {
        VStack(spacing: 0) {
            TabBarView()
            Divider()
            if let document = workspace.selectedDocument {
                if workspace.find.isVisible {
                    FindBarView(find: workspace.find)
                    Divider()
                }
                EditorView(
                    document: document,
                    configuration: workspace.editorConfiguration,
                    theme: workspace.theme,
                    onCreate: { workspace.editorDidAppear($0) }
                )
                .id(document.id)
                Divider()
                StatusBarView(document: document)
            } else {
                ContentUnavailableView {
                    Label("No File Open", systemImage: "doc.text")
                } description: {
                    Text("Select a file in the sidebar, or press \u{2318}N for a new one.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: workspace.theme.colors.editorBackground).opacity(workspace.editorConfiguration.clampedBackgroundOpacity))
            }
        }
    }
}
