import Foundation

/// Builds the current command list from workspace state. Menus and the palette both
/// end up calling the same `Workspace` methods; this list is just the catalog.
@MainActor
enum CommandRegistry {
    static func commands(for workspace: Workspace) -> [Command] {
        let hasDocument = workspace.selectedDocument != nil
        let configuration = workspace.editorConfiguration
        var commands: [Command] = [
            Command(id: "file.new", title: "File: New", shortcut: "\u{2318}N") { workspace.newDocument() },
            Command(id: "file.open", title: "File: Open\u{2026}", shortcut: "\u{2318}O") { workspace.openFilePanel() },
            Command(id: "file.openFolder", title: "File: Open Folder\u{2026}", shortcut: "\u{21E7}\u{2318}O") { workspace.openFolderPanel() },
            Command(id: "file.save", title: "File: Save", shortcut: "\u{2318}S", isEnabled: hasDocument) { Task { await workspace.save() } },
            Command(id: "file.saveAs", title: "File: Save As\u{2026}", shortcut: "\u{21E7}\u{2318}S", isEnabled: hasDocument) { Task { await workspace.saveAs() } },
            Command(id: "file.closeTab", title: "File: Close Tab", shortcut: "\u{2318}W", isEnabled: hasDocument) { workspace.closeSelectedTab() },
            Command(id: "file.quickOpen", title: "Go to File\u{2026}", shortcut: "\u{2318}P") { workspace.showQuickOpen() },
            Command(id: "edit.find", title: "Find", shortcut: "\u{2318}F", isEnabled: hasDocument) { workspace.showFind(withReplace: false) },
            Command(id: "edit.replace", title: "Find and Replace", shortcut: "\u{2325}\u{2318}F", isEnabled: hasDocument) { workspace.showFind(withReplace: true) },
            Command(id: "view.softWrap", title: "View: \(configuration.softWrap ? "Disable" : "Enable") Soft Wrap", shortcut: "\u{2325}Z") { workspace.toggleSoftWrap() },
            Command(id: "view.lineNumbers", title: "View: \(configuration.showLineNumbers ? "Hide" : "Show") Line Numbers") { workspace.toggleLineNumbers() },
            Command(id: "view.currentLine", title: "View: \(configuration.highlightCurrentLine ? "Disable" : "Enable") Current Line Highlight") {
                workspace.editorConfiguration.highlightCurrentLine.toggle()
            },
            Command(id: "view.fontBigger", title: "View: Increase Font Size", shortcut: "\u{2318}=") { workspace.adjustFontSize(by: 1) },
            Command(id: "view.fontSmaller", title: "View: Decrease Font Size", shortcut: "\u{2318}-") { workspace.adjustFontSize(by: -1) },
            Command(id: "view.fontReset", title: "View: Reset Font Size", shortcut: "\u{2318}0") { workspace.resetFontSize() },
            Command(id: "settings.open", title: "Preferences: Open Settings", shortcut: "\u{2318},") { workspace.showSettings() },
        ]
        for theme in workspace.availableThemes {
            commands.append(Command(id: "theme.\(theme.name)", title: "Preferences: Color Theme: \(theme.name)", isEnabled: theme != workspace.theme) {
                workspace.theme = theme
            })
        }
        return commands
    }
}
