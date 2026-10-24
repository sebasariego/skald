import XCTest
@testable import Quill

@MainActor
final class DirtyStateTests: XCTestCase {
    func testUndoBackToSavedStateClearsDirty() {
        let document = Quill.Document(url: nil, text: "abc")
        let view = CodeTextView(document: document)
        view.insertText("X", replacementRange: NSRange(location: 3, length: 0))
        XCTAssertTrue(document.isDirty)
        document.undoManager.undo()
        XCTAssertEqual(document.text, "abc")
        XCTAssertFalse(document.isDirty, "undo returned to the saved text")
        document.undoManager.redo()
        XCTAssertTrue(document.isDirty)
    }

    func testSaveThenUndoIsDirtyAgain() async throws {
        let directory = try TestTemporaryDirectory()
        defer { directory.remove() }
        let url = try directory.file("d.txt", contents: Data("one".utf8))
        let store = DocumentStore()
        let document = try await store.open(url)
        let view = CodeTextView(document: document)
        view.insertText("!", replacementRange: NSRange(location: 3, length: 0))
        try await store.save(document)
        XCTAssertFalse(document.isDirty)
        document.undoManager.undo()
        XCTAssertTrue(document.isDirty, "text now differs from what was saved")
    }

    func testTrimOnSaveThroughEditorIsUndoable() async throws {
        let directory = try TestTemporaryDirectory()
        defer { directory.remove() }
        let url = try directory.file("t.txt", contents: Data("a  \nb\t\n".utf8))
        let store = DocumentStore()
        let document = try await store.open(url)
        let view = CodeTextView(document: document)
        try await store.save(document, trimmingTrailingWhitespace: true, editor: view)
        XCTAssertEqual(document.text, "a\nb\n")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a\nb\n")
        XCTAssertTrue(document.undoManager.canUndo)
        document.undoManager.undo()
        XCTAssertEqual(document.text, "a  \nb\t\n")
        XCTAssertTrue(document.isDirty)
    }

    func testStatusTracksCaret() {
        let document = Quill.Document(url: nil, text: "ab\ncdef\n")
        let view = CodeTextView(document: document)
        let status = EditorStatus()
        status.track(view)
        view.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertEqual(status.line, 2)
        XCTAssertEqual(status.column, 3)
        view.setSelectedRange(NSRange(location: 1, length: 5))
        XCTAssertEqual(status.selectedCharacters, 5)
        XCTAssertEqual(status.selectedLines, 2)
    }

    func testTabSwitching() {
        let workspace = Workspace(settingsStore: SettingsStore(defaults: UserDefaults(suiteName: "dev.local.quill.tests.tabs") ?? .standard), themes: [ThemeLoader.fallbackTheme])
        let a = workspace.documents.newUntitled()
        let b = workspace.documents.newUntitled()
        let c = workspace.documents.newUntitled()
        workspace.selectTab(at: 0)
        XCTAssertEqual(workspace.selectedDocumentID, a.id)
        workspace.selectAdjacentTab(offset: 1)
        XCTAssertEqual(workspace.selectedDocumentID, b.id)
        workspace.selectAdjacentTab(offset: -2)
        XCTAssertEqual(workspace.selectedDocumentID, c.id, "wraps around")
        workspace.selectTab(at: 9)
        XCTAssertEqual(workspace.selectedDocumentID, c.id, "out of range is ignored")
    }
}
