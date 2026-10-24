import AppKit
import Observation

/// Caret position and selection size of the active editor, for the status bar.
@MainActor
@Observable
final class EditorStatus {
    /// One-based.
    private(set) var line = 1
    /// One-based, in characters.
    private(set) var column = 1
    private(set) var selectedCharacters = 0
    private(set) var selectedLines = 0

    @ObservationIgnored private weak var textView: CodeTextView?

    func track(_ textView: CodeTextView) {
        self.textView?.onSelectionChange = nil
        self.textView = textView
        textView.onSelectionChange = { [weak self] range in
            self?.update(for: range, in: textView)
        }
        update(for: textView.selectedRange(), in: textView)
    }

    func clear() {
        textView?.onSelectionChange = nil
        textView = nil
        line = 1
        column = 1
        selectedCharacters = 0
        selectedLines = 0
    }

    private func update(for range: NSRange, in textView: CodeTextView) {
        let index = textView.document.lineIndex
        let lineNumber = index.lineNumber(forOffset: range.location)
        line = lineNumber + 1
        column = range.location - index.startOffset(ofLine: lineNumber) + 1
        selectedCharacters = range.length
        selectedLines = range.length == 0 ? 0 : index.lineNumber(forOffset: NSMaxRange(range)) - lineNumber + 1
    }
}
