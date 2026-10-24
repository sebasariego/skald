import AppKit

/// Asked when a file with unsaved edits changes on disk.
enum ExternalChangePrompt {
    enum Choice {
        case reload
        case keepMine
    }

    @MainActor
    static func run(for document: Document) -> Choice {
        let alert = NSAlert()
        alert.messageText = "\u{201C}\(document.displayName)\u{201D} has changed on disk."
        alert.informativeText = "You have unsaved changes. Reloading will discard them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep My Changes")
        alert.addButton(withTitle: "Reload")
        return alert.runModal() == .alertSecondButtonReturn ? .reload : .keepMine
    }
}
