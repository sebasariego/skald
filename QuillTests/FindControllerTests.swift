import XCTest
@testable import Quill

@MainActor
final class FindControllerTests: XCTestCase {
    private var scrollViews: [NSScrollView] = []

    override func tearDown() {
        scrollViews.removeAll()
    }

    private func makeEditor(text: String) -> (CodeTextView, Quill.Document) {
        let document = Quill.Document(url: nil, text: text)
        let scrollView = EditorView.makeScrollView(document: document, configuration: EditorConfiguration(), theme: ThemeLoader.fallbackTheme)
        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        scrollViews.append(scrollView)
        return ((scrollView.documentView as? CodeTextView) ?? CodeTextView(document: document), document)
    }

    func testShowSearchesAndNavigatesWithWrap() async {
        let (textView, _) = makeEditor(text: "a b a b a")
        let find = FindController()
        find.attach(textView)
        find.show(withReplace: false)
        find.query = "a"
        await find.waitForSearch()
        try? await Task.sleep(for: .milliseconds(120))
        await find.waitForSearch()

        XCTAssertEqual(find.matches.count, 3)
        XCTAssertEqual(find.statusText, "3 results")
        find.findNext()
        XCTAssertEqual(find.currentIndex, 0)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 1))
        find.findNext()
        find.findNext()
        XCTAssertEqual(find.currentIndex, 2)
        find.findNext()
        XCTAssertEqual(find.currentIndex, 0, "wraps to the first match")
        find.findPrevious()
        XCTAssertEqual(find.currentIndex, 2, "wraps backwards")
        XCTAssertEqual(find.statusText, "3 of 3")
        XCTAssertEqual(textView.searchMatches.count, 3)
    }

    func testReplaceAllIsOneUndoStep() async {
        let (textView, document) = makeEditor(text: "x1 x2 x3")
        let find = FindController()
        find.attach(textView)
        find.show(withReplace: true)
        find.query = "x(\\d)"
        find.isRegex = true
        find.replacement = "y$1"
        try? await Task.sleep(for: .milliseconds(120))
        await find.waitForSearch()
        XCTAssertEqual(find.matches.count, 3)

        find.replaceAll()
        await find.waitForSearch()
        XCTAssertEqual(document.text, "y1 y2 y3")
        XCTAssertTrue(find.matches.isEmpty)

        document.undoManager.undo()
        XCTAssertEqual(document.text, "x1 x2 x3", "a single undo restores every replacement")
    }

    func testReplaceCurrentAdvancesToNextMatch() async {
        let (textView, document) = makeEditor(text: "cat cat cat")
        let find = FindController()
        find.attach(textView)
        find.show(withReplace: true)
        find.query = "cat"
        find.replacement = "dog"
        try? await Task.sleep(for: .milliseconds(120))
        await find.waitForSearch()
        find.findNext()
        XCTAssertEqual(find.currentIndex, 0)

        find.replaceCurrent()
        await find.waitForSearch()
        XCTAssertEqual(document.text, "dog cat cat")
        XCTAssertEqual(find.matches.count, 2)
        XCTAssertEqual(find.currentIndex, 0)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 3))
    }

    func testInvalidRegexShowsErrorAndNoMatches() async {
        let (textView, _) = makeEditor(text: "abc")
        let find = FindController()
        find.attach(textView)
        find.show(withReplace: false)
        find.isRegex = true
        find.query = "("
        try? await Task.sleep(for: .milliseconds(120))
        await find.waitForSearch()
        XCTAssertTrue(find.matches.isEmpty)
        XCTAssertEqual(find.statusText, "Invalid regular expression")
    }

    func testHideClearsMatchesInView() async {
        let (textView, _) = makeEditor(text: "q q")
        let find = FindController()
        find.attach(textView)
        find.show(withReplace: false)
        find.query = "q"
        try? await Task.sleep(for: .milliseconds(120))
        await find.waitForSearch()
        XCTAssertEqual(textView.searchMatches.count, 2)
        find.hide()
        XCTAssertTrue(textView.searchMatches.isEmpty)
        XCTAssertFalse(find.isVisible)
    }
}
