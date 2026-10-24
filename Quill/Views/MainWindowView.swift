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
        .navigationSubtitle(workspace.folderTree.root?.name ?? "")
        // Icon-only items at the trailing edge, in three groups. The id makes the toolbar
        // customizable from its context menu, as on any Mac app.
        .toolbar(id: "main") {
            ToolbarItem(id: "newFile", placement: .primaryAction) {
                Button { workspace.newDocument() } label: { Label("New File", systemImage: "doc.badge.plus") }
                    .help("New File (\u{2318}N)")
            }
            ToolbarItem(id: "openFolder", placement: .primaryAction) {
                Button { workspace.openFolderPanel() } label: { Label("Open Folder", systemImage: "folder.badge.plus") }
                    .help("Open Folder (\u{21E7}\u{2318}O)")
            }
            ToolbarItem(id: "spacer1", placement: .primaryAction, showsByDefault: true) {
                Spacer().frame(width: 8)
            }
            ToolbarItem(id: "goToFile", placement: .primaryAction) {
                Button { workspace.showQuickOpen() } label: { Label("Go to File", systemImage: "magnifyingglass") }
                    .help("Go to File (\u{2318}P)")
            }
            ToolbarItem(id: "find", placement: .primaryAction) {
                Button { workspace.showFind(withReplace: false) } label: { Label("Find", systemImage: "text.magnifyingglass") }
                    .help("Find (\u{2318}F)")
                    .disabled(workspace.selectedDocument == nil)
            }
            ToolbarItem(id: "commandPalette", placement: .primaryAction) {
                Button { workspace.showCommandPalette() } label: { Label("Command Palette", systemImage: "command") }
                    .help("Command Palette (\u{21E7}\u{2318}P)")
            }
            ToolbarItem(id: "spacer2", placement: .primaryAction, showsByDefault: true) {
                Spacer().frame(width: 8)
            }
            ToolbarItem(id: "settings", placement: .primaryAction) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .help("Settings (\u{2318},)")
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
