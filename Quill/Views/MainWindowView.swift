import SwiftUI

struct MainWindowView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
        } detail: {
            EditorAreaView()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    workspace.openFolderPanel()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .help("Open Folder (\u{21E7}\u{2318}O)")
            }
        }
        .alert(item: $workspace.presentedError) { error in
            Alert(title: Text(error.title), message: Text(error.message))
        }
        .overlay(alignment: .top) {
            if workspace.palette.isPresented {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { workspace.palette.dismiss() }
                    PaletteView(palette: workspace.palette)
                        .padding(.top, 48)
                }
                .transition(.opacity)
            }
        }
    }
}
