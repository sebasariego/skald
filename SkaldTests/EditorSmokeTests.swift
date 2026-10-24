import XCTest
@testable import Skald

/// Builds the real editor stack without a window and renders it offscreen, so a
/// crash in layout, gutter drawing or key handling shows up here first.
@MainActor
final class EditorSmokeTests: XCTestCase {
    private func makeEditor(text: String, configuration: EditorConfiguration = EditorConfiguration()) -> (NSScrollView, CodeTextView, Skald.Document) {
        let document = Skald.Document(url: nil, text: text)
        let scrollView = EditorView.makeScrollView(document: document, configuration: configuration, theme: ThemeLoader.fallbackTheme)
        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        scrollView.layoutSubtreeIfNeeded()
        guard let textView = scrollView.documentView as? CodeTextView else {
            XCTFail("documentView is not a CodeTextView")
            return (scrollView, CodeTextView(document: document), document)
        }
        return (scrollView, textView, document)
    }

    func testRendersOffscreenWithGutter() {
        let (scrollView, textView, _) = makeEditor(text: (1...200).map { "line \($0)" }.joined(separator: "\n"))
        textView.setSelectedRange(NSRange(location: 12, length: 0))
        XCTAssertTrue(scrollView.rulersVisible)
        XCTAssertNotNil(textView.gutter)
        XCTAssertGreaterThan(textView.gutter?.ruleThickness ?? 0, 20)

        guard let bitmap = scrollView.bitmapImageRepForCachingDisplay(in: scrollView.bounds) else {
            return XCTFail("no bitmap")
        }
        scrollView.cacheDisplay(in: scrollView.bounds, to: bitmap)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        assertStillTextKit2(textView)
    }

    func testReturnAutoIndentsAndTabInsertsSpaces() {
        let (_, textView, document) = makeEditor(text: "    foo {")
        textView.setSelectedRange(NSRange(location: 9, length: 0))
        textView.insertNewline(nil)
        XCTAssertEqual(document.text, "    foo {\n        ")
        XCTAssertEqual(textView.selectedRange().location, document.text.utf16.count)

        textView.insertTab(nil)
        XCTAssertEqual(document.text, "    foo {\n            ")

        textView.insertBacktab(nil)
        XCTAssertEqual(document.text, "    foo {\n        ")
        XCTAssertTrue(document.undoManager.canUndo)
        assertStillTextKit2(textView)
    }

    func testTabWithMultiLineSelectionIndentsBlock() {
        let (_, textView, document) = makeEditor(text: "a\nb\nc")
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        textView.insertTab(nil)
        XCTAssertEqual(document.text, "    a\n    b\nc")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 11))
        textView.insertBacktab(nil)
        XCTAssertEqual(document.text, "a\nb\nc")
        assertStillTextKit2(textView)
    }

    func testPasteNormalizesCRLF() {
        let (_, textView, document) = makeEditor(text: "")
        textView.insertText("x\r\ny\rz", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(document.text, "x\ny\nz")
        XCTAssertEqual(document.lineIndex.lineCount, 3)
        assertStillTextKit2(textView)
    }

    func testSoftWrapToggleReconfiguresContainer() {
        var configuration = EditorConfiguration()
        let (scrollView, textView, _) = makeEditor(text: String(repeating: "word ", count: 400), configuration: configuration)
        XCTAssertTrue(textView.textContainer?.widthTracksTextView ?? false)
        XCTAssertFalse(scrollView.hasHorizontalScroller)

        configuration.softWrap = false
        textView.apply(configuration)
        XCTAssertFalse(textView.textContainer?.widthTracksTextView ?? true)
        XCTAssertTrue(scrollView.hasHorizontalScroller)
        XCTAssertTrue(textView.isHorizontallyResizable)

        configuration.softWrap = true
        textView.apply(configuration)
        XCTAssertTrue(textView.textContainer?.widthTracksTextView ?? false)
        assertStillTextKit2(textView)
    }

    func testFontSizeChangeReappliesAttributes() {
        var configuration = EditorConfiguration()
        let (_, textView, document) = makeEditor(text: "abc", configuration: configuration)
        configuration.fontSize = 18
        textView.apply(configuration)
        let font = document.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 18)
        XCTAssertEqual((textView.typingAttributes[.font] as? NSFont)?.pointSize, 18)
        assertStillTextKit2(textView)
    }

    func testBackgroundOpacityAppliesToEditorAndGutter() {
        var configuration = EditorConfiguration()
        configuration.backgroundOpacity = 0.6
        let (scrollView, textView, _) = makeEditor(text: "abc", configuration: configuration)
        XCTAssertEqual(textView.backgroundColor.alphaComponent, 0.6, accuracy: 0.001)
        XCTAssertFalse(scrollView.drawsBackground)
        configuration.backgroundOpacity = 0.1 // below the floor
        textView.apply(configuration)
        XCTAssertEqual(textView.backgroundColor.alphaComponent, EditorConfiguration.minimumBackgroundOpacity, accuracy: 0.001)
        configuration.backgroundOpacity = 1
        textView.apply(configuration)
        XCTAssertEqual(textView.backgroundColor.alphaComponent, 1, accuracy: 0.001)
        XCTAssertTrue(scrollView.drawsBackground)
        assertStillTextKit2(textView)
    }

    /// Any `layoutManager` access downgrades the view to TextKit 1; check after exercising it.
    private func assertStillTextKit2(_ textView: CodeTextView, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(textView.textLayoutManager, "view fell back to TextKit 1", file: file, line: line)
    }
}
