import AppKit

/// The standard "Do you want to save the changes?" sheet, run modally.
enum UnsavedChangesPrompt {
    enum Choice {
        case save
        case discard
        case cancel
    }

    @MainActor
    static func run(for document: Document) -> Choice {
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to \u{201C}\(document.displayName)\u{201D}?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertThirdButtonReturn: return .discard
        default: return .cancel
        }
    }
}
