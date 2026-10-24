import SwiftUI

/// An invisible overlay that reacts to the middle mouse button and lets every other
/// event fall through to the SwiftUI view underneath. SwiftUI has no middle-click gesture.
struct MiddleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }

    final class CatcherView: NSView {
        var action: (() -> Void)?

        /// Claim the hit only for middle-button events; left and right clicks pass through.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
                return event.buttonNumber == 2 ? super.hitTest(point) : nil
            default:
                return nil
            }
        }

        override func otherMouseUp(with event: NSEvent) {
            guard event.buttonNumber == 2, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            action?()
        }
    }
}
