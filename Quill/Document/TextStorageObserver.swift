import AppKit

/// Bridges `NSTextStorageDelegate` to a closure so `Document` can stay a plain Swift class.
final class TextStorageObserver: NSObject, NSTextStorageDelegate {
    /// Called after characters changed: the new range and the change in length.
    var onCharactersChanged: ((NSRange, Int) -> Void)?

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        onCharactersChanged?(editedRange, delta)
    }
}
