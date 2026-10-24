import XCTest
@testable import Quill

@MainActor
final class DocumentStoreTests: XCTestCase {
    private var directory: TestTemporaryDirectory!

    override func setUpWithError() throws {
        directory = try TestTemporaryDirectory()
    }

    override func tearDown() {
        directory.remove()
    }

    func testOpenReturnsSameDocumentForSameURL() async throws {
        let url = try directory.file("a.swift", contents: Data("let a = 1\n".utf8))
        let store = DocumentStore()
        let first = try await store.open(url)
        let second = try await store.open(url)
        XCTAssertTrue(first === second)
        XCTAssertEqual(store.documents.count, 1)
        XCTAssertEqual(first.text, "let a = 1\n")
        XCTAssertFalse(first.isDirty)
    }

    func testEditingMarksDirtyAndSaveClearsIt() async throws {
        let url = try directory.file("b.txt", contents: Data("x\r\n".utf8))
        let store = DocumentStore()
        let document = try await store.open(url)
        document.textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "y")
        XCTAssertTrue(document.isDirty)
        try await store.save(document)
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "yx\r\n", "CRLF must survive a round trip")
    }

    func testSaveAsRetargetsDocument() async throws {
        let store = DocumentStore()
        let document = store.newUntitled()
        XCTAssertEqual(document.displayName, "Untitled")
        document.textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "hello")
        let target = directory.url.appendingPathComponent("new.txt")
        try await store.save(document, to: target)
        XCTAssertEqual(document.url, target)
        XCTAssertEqual(document.displayName, "new.txt")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "hello")
    }

    func testCloseRemovesDocument() async throws {
        let store = DocumentStore()
        let document = store.newUntitled()
        store.close(document)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertNil(store.document(withID: document.id))
    }

    func testReloadReplacesTextAndClearsDirty() async throws {
        let url = try directory.file("c.txt", contents: Data("old".utf8))
        let store = DocumentStore()
        let document = try await store.open(url)
        document.textStorage.replaceCharacters(in: NSRange(location: 0, length: 3), with: "edited")
        try Data("new".utf8).write(to: url)
        try await store.reload(document)
        XCTAssertEqual(document.text, "new")
        XCTAssertFalse(document.isDirty)
        XCTAssertFalse(document.undoManager.canUndo)
    }
}
