import SwiftUI

/// Invisible view that mirrors document state onto the hosting `NSWindow`: the edited
/// dot in the close button and the file proxy icon in the title bar.
struct WindowStateView: NSViewRepresentable {
    let representedURL: URL?
    let isEdited: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.representedURL = representedURL
            window.isDocumentEdited = isEdited
        }
    }
}
