import SwiftUI

/// File menu. "Close Tab" sits in the `.newItem` group so its Cmd+W is found
/// before the system "Close" item; `AppDelegate` moves that one to Cmd+Shift+W.
struct QuillCommands: Commands {
    let workspace: Workspace

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { workspace.newDocument() }
                .keyboardShortcut("n")
            Button("Open\u{2026}") { workspace.openFilePanel() }
                .keyboardShortcut("o")
            Button("Open Folder\u{2026}") { workspace.openFolderPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            // Always enabled: a disabled item would let Cmd+W fall through to the system "Close" window item.
            Button("Close Tab") { workspace.closeSelectedTab() }
                .keyboardShortcut("w")
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find\u{2026}") { workspace.showFind(withReplace: false) }
                .keyboardShortcut("f")
                .disabled(workspace.selectedDocument == nil)
            Button("Find and Replace\u{2026}") { workspace.showFind(withReplace: true) }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(workspace.selectedDocument == nil)
            Button("Find Next") { workspace.find.findNext() }
                .keyboardShortcut("g")
                .disabled(workspace.find.matches.isEmpty)
            Button("Find Previous") { workspace.find.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(workspace.find.matches.isEmpty)
            Button("Use Selection for Find") { workspace.find.useSelectionForFind() }
                .keyboardShortcut("e")
                .disabled(workspace.selectedDocument == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Go to File\u{2026}") { workspace.showQuickOpen() }
                .keyboardShortcut("p")
        }
        CommandGroup(after: .sidebar) {
            Divider()
            Button("Command Palette\u{2026}") { workspace.showCommandPalette() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Toggle("Soft Wrap", isOn: binding(\.softWrap))
                .keyboardShortcut("z", modifiers: [.option])
            Toggle("Line Numbers", isOn: binding(\.showLineNumbers))
            Toggle("Highlight Current Line", isOn: binding(\.highlightCurrentLine))
            Divider()
            Button("Increase Font Size") { workspace.adjustFontSize(by: 1) }
                .keyboardShortcut("=", modifiers: [.command])
            Button("Decrease Font Size") { workspace.adjustFontSize(by: -1) }
                .keyboardShortcut("-", modifiers: [.command])
            Button("Reset Font Size") { workspace.resetFontSize() }
                .keyboardShortcut("0", modifiers: [.command])
            Button("Font and Appearance\u{2026}") { workspace.showSettings() }
        }
        CommandGroup(before: .windowList) {
            Button("Next Tab") { workspace.selectAdjacentTab(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { workspace.selectAdjacentTab(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            ForEach(1..<10) { index in
                Button("Tab \(index)") { workspace.selectTab(at: index - 1) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: [.command])
            }
            Divider()
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { Task { await workspace.save() } }
                .keyboardShortcut("s")
                .disabled(workspace.selectedDocument == nil)
            Button("Save As\u{2026}") { Task { await workspace.saveAs() } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(workspace.selectedDocument == nil)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<EditorConfiguration, Bool>) -> Binding<Bool> {
        Binding(
            get: { workspace.editorConfiguration[keyPath: keyPath] },
            set: { workspace.editorConfiguration[keyPath: keyPath] = $0 }
        )
    }
}
