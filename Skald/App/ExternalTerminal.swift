import AppKit

/// Terminal apps Skald can hand a folder to. The app opens a new window there.
struct ExternalTerminal: Identifiable, Equatable, Sendable {
    let id: String
    let name: String

    static let automatic = ExternalTerminal(id: "automatic", name: "Automatic")
    static let known: [ExternalTerminal] = [
        ExternalTerminal(id: "com.mitchellh.ghostty", name: "Ghostty"),
        ExternalTerminal(id: "com.googlecode.iterm2", name: "iTerm"),
        ExternalTerminal(id: "dev.warp.Warp-Stable", name: "Warp"),
        ExternalTerminal(id: "net.kovidgoyal.kitty", name: "kitty"),
        ExternalTerminal(id: "org.alacritty", name: "Alacritty"),
        ExternalTerminal(id: "com.github.wez.wezterm", name: "WezTerm"),
        ExternalTerminal(id: "com.apple.Terminal", name: "Terminal"),
    ]

    /// Known terminals that are installed, in preference order; Terminal.app is always last.
    @MainActor
    static func installed() -> [ExternalTerminal] {
        known.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }

    /// The app to use for a stored preference; `automatic` or a missing app falls back to
    /// the first installed terminal.
    @MainActor
    static func resolve(preferredID: String?) -> ExternalTerminal? {
        let available = installed()
        if let preferredID, preferredID != automatic.id, let match = available.first(where: { $0.id == preferredID }) {
            return match
        }
        return available.first
    }

    /// Opens a new terminal window at `directory`.
    @MainActor
    func open(directory: URL, completion: @escaping @MainActor @Sendable (Error?) -> Void) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            completion(CocoaError(.fileNoSuchFile))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([directory], withApplicationAt: appURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(error) }
            }
        }
    }
}
