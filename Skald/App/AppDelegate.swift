import AppKit

/// Owns the single `Workspace` so that both the SwiftUI scene and AppKit
/// callbacks (dock drops, termination) talk to the same model.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let workspace = Workspace()

    private var receivedOpenRequest = false

    private var windowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI finishes assembling the main menu after this callback returns.
        DispatchQueue.main.async { [weak self] in
            self?.remapSystemCloseShortcut()
        }
        // Let the tab bar's material run straight into the toolbar, without a hairline between.
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { Self.removeTitlebarSeparator(from: window) }
        }
        DispatchQueue.main.async {
            NSApp.windows.forEach(Self.removeTitlebarSeparator(from:))
        }
        if !receivedOpenRequest {
            workspace.restoreSession()
        }
    }

    /// Finder "Open With", drops on the Dock icon, and `open -a Skald <path>`.
    func application(_ application: NSApplication, open urls: [URL]) {
        receivedOpenRequest = true
        workspace.open(urls: urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspace.saveSession()
    }

    /// Closing the window keeps documents in memory; clicking the Dock icon reopens it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirty = workspace.documents.documents.filter(\.isDirty)
        guard !dirty.isEmpty else { return .terminateNow }
        Task { @MainActor in
            for document in dirty {
                switch UnsavedChangesPrompt.run(for: document) {
                case .save:
                    guard await workspace.save(document) else {
                        NSApp.reply(toApplicationShouldTerminate: false)
                        return
                    }
                case .discard:
                    continue
                case .cancel:
                    NSApp.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private static func removeTitlebarSeparator(from window: NSWindow) {
        guard window.styleMask.contains(.titled) else { return }
        window.titlebarSeparatorStyle = .none
    }

    /// Cmd+W belongs to "Close Tab". Move the system "Close" (window) item to Cmd+Shift+W.
    private func remapSystemCloseShortcut() {
        guard let fileMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "File" })?.submenu else {
            return
        }
        for item in fileMenu.items where item.action == #selector(NSWindow.performClose(_:)) {
            item.keyEquivalent = "w"
            item.keyEquivalentModifierMask = [.command, .shift]
        }
    }
}
