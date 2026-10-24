import XCTest
@testable import Skald

/// The undo stack belongs to the document, so it must survive the editor view being rebuilt.
@MainActor
final class UndoAcrossViewsTests: XCTestCase {
    func testUndoSurvivesViewRecreation() {
        let document = Document(url: nil)
        var view: CodeTextView? = CodeTextView(document: document)
        view?.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(document.text, "hello")
        XCTAssertTrue(document.isDirty)
        XCTAssertTrue(document.undoManager.canUndo)

        view = nil
        let second = CodeTextView(document: document)
        second.undoManager?.undo()
        XCTAssertEqual(document.text, "")
        XCTAssertTrue(document.undoManager.canRedo)
        second.undoManager?.redo()
        XCTAssertEqual(document.text, "hello")
    }

    func testTextViewUsesTextKit2() {
        let document = Document(url: nil, text: "a\nb\n")
        let view = CodeTextView(document: document)
        XCTAssertNotNil(view.textLayoutManager)
        XCTAssertTrue(view.textContentStorage?.textStorage === document.textStorage)
    }
}
