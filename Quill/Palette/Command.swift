import Foundation

/// A named action for the command palette and, later, anything else that wants to run
/// editor features without going through a menu.
struct Command: Identifiable {
    let id: String
    let title: String
    let shortcut: String?
    let isEnabled: Bool
    let perform: @MainActor () -> Void

    init(id: String, title: String, shortcut: String? = nil, isEnabled: Bool = true, perform: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.perform = perform
    }
}
