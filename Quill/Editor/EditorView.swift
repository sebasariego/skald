import SwiftUI

/// Hosts one `CodeTextView` for one `Document`. Use `.id(document.id)` at the call
/// site so SwiftUI builds a fresh view per document instead of re-pointing this one.
struct EditorView: NSViewRepresentable {
    let document: Document
    let configuration: EditorConfiguration
    let theme: Theme
    /// Called once with the new text view, so the workspace knows which editor is active.
    var onCreate: ((CodeTextView) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = Self.makeScrollView(document: document, configuration: configuration, theme: theme)
        if let textView = scrollView.documentView as? CodeTextView {
            onCreate?(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        scrollView.rulersVisible = configuration.showLineNumbers
        textView.apply(configuration, theme: theme)
    }

    /// The AppKit stack: scroll view, gutter ruler and text view.
    static func makeScrollView(document: Document, configuration: EditorConfiguration, theme: Theme) -> NSScrollView {
        let textView = CodeTextView(document: document)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let gutter = GutterView(scrollView: scrollView, textView: textView)
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = gutter
        scrollView.rulersVisible = configuration.showLineNumbers
        textView.gutter = gutter

        textView.apply(configuration, theme: theme)
        textView.didAttachToScrollView(scrollView)
        return scrollView
    }
}
