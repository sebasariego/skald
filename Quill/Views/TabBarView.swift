import SwiftUI

/// Open documents as a row of pill-shaped tabs on a translucent bar, in the manner of
/// Xcode and Safari. A plain row, not a ScrollView: a ScrollView at the top edge grows
/// into the toolbar's safe area and its content ends up half under the toolbar.
struct TabBarView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(workspace.documents.documents) { document in
                TabItemView(
                    document: document,
                    isSelected: document.id == workspace.selectedDocumentID,
                    select: { workspace.selectedDocumentID = document.id },
                    close: { Task { await workspace.close(document) } }
                )
                .frame(maxWidth: 240)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(.bar, ignoresSafeAreaEdges: [])
    }
}
