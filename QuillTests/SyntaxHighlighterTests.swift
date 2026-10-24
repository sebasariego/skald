import XCTest
@testable import Quill

@MainActor
final class SyntaxHighlighterTests: XCTestCase {
    private var theme: Theme!
    /// Keeps the scroll views alive for the duration of a test; dropping one detaches its text view.
    private var retainedScrollViews: [NSScrollView] = []
    private let language = LanguageDefinition(id: "fake", displayName: "Fake", fileExtensions: ["fake"], lineComment: nil)

    override func setUpWithError() throws {
        theme = try ThemeLoader.load(from: TestResources.url("Quill/Resources/Themes/quill-dark.theme.json"))
    }

    private func makeEditor(text: String, parser: FakeSyntaxParser) -> (CodeTextView, Quill.Document, SyntaxHighlighter) {
        let document = Quill.Document(url: nil, text: text)
        let highlighter = SyntaxHighlighter(language: language, parser: parser, document: document, theme: theme)
        document.installHighlighterForTesting(highlighter)
        let scrollView = EditorView.makeScrollView(document: document, configuration: EditorConfiguration(), theme: theme)
        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        retainedScrollViews.append(scrollView)
        let textView = scrollView.documentView as? CodeTextView
        return (textView ?? CodeTextView(document: document), document, highlighter)
    }

    override func tearDown() {
        retainedScrollViews.removeAll()
    }

    private func foregroundColor(at offset: Int, in textView: CodeTextView) -> NSColor? {
        guard let contentStorage = textView.textContentStorage,
              let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: offset) else { return nil }
        var color: NSColor?
        textView.textLayoutManager?.enumerateRenderingAttributes(from: location, reverse: false) { _, attributes, range in
            if range.contains(location) {
                color = attributes[.foregroundColor] as? NSColor
            }
            return false
        }
        return color
    }

    func testInitialParsePaintsRenderingAttributes() async throws {
        let parser = FakeSyntaxParser(keywords: ["let"])
        let (textView, _, highlighter) = makeEditor(text: "let x = 42", parser: parser)
        await highlighter.waitForPendingParse()

        let keywordColor = CaptureScopeMap(theme: theme).style(for: "keyword")?.foreground
        let numberColor = CaptureScopeMap(theme: theme).style(for: "number")?.foreground
        XCTAssertEqual(foregroundColor(at: 0, in: textView), keywordColor)
        XCTAssertEqual(foregroundColor(at: 8, in: textView), numberColor)
        XCTAssertNil(foregroundColor(at: 4, in: textView), "identifiers keep the base color")
        XCTAssertEqual(parser.parseCount, 1)
        XCTAssertEqual(parser.receivedEdits.first, .some(nil), "first parse discards any old tree")
        XCTAssertNotNil(textView.textLayoutManager)
    }

    func testEditsAreForwardedAndRepainted() async throws {
        let parser = FakeSyntaxParser(keywords: ["let", "var"])
        let (textView, document, highlighter) = makeEditor(text: "x = 1", parser: parser)
        await highlighter.waitForPendingParse()

        textView.insertText("var ", replacementRange: NSRange(location: 0, length: 0))
        try await Task.sleep(for: .milliseconds(60))
        await highlighter.waitForPendingParse()

        XCTAssertEqual(parser.parseCount, 2)
        let edits = try XCTUnwrap(parser.receivedEdits.last ?? nil)
        XCTAssertEqual(edits.count, 1)
        XCTAssertEqual(edits[0].startOffset, 0)
        XCTAssertEqual(edits[0].oldEndOffset, 0)
        XCTAssertEqual(edits[0].newEndOffset, 4)
        XCTAssertEqual(edits[0].newEndPoint, TextPoint(row: 0, column: 4))
        XCTAssertEqual(document.text, "var x = 1")
        XCTAssertEqual(foregroundColor(at: 0, in: textView), CaptureScopeMap(theme: theme).style(for: "keyword")?.foreground)
    }

    func testMultilineEditPointsComeFromLineIndex() async throws {
        let parser = FakeSyntaxParser(keywords: [])
        let (textView, _, highlighter) = makeEditor(text: "ab\ncd\nef", parser: parser)
        await highlighter.waitForPendingParse()
        // Replace "cd\ne" (offsets 3..<7) with "Z\n\nQ".
        textView.insertText("Z\n\nQ", replacementRange: NSRange(location: 3, length: 4))
        try await Task.sleep(for: .milliseconds(60))
        await highlighter.waitForPendingParse()
        let edit = try XCTUnwrap((parser.receivedEdits.last ?? nil)?.first)
        XCTAssertEqual(edit.startPoint, TextPoint(row: 1, column: 0))
        XCTAssertEqual(edit.oldEndPoint, TextPoint(row: 2, column: 1))
        XCTAssertEqual(edit.newEndPoint, TextPoint(row: 3, column: 1))
    }

    func testThemeChangeRepaints() async throws {
        let parser = FakeSyntaxParser(keywords: ["let"])
        let (textView, _, highlighter) = makeEditor(text: "let a", parser: parser)
        await highlighter.waitForPendingParse()
        let light = try ThemeLoader.load(from: TestResources.url("Quill/Resources/Themes/quill-light.theme.json"))
        highlighter.theme = light
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(foregroundColor(at: 0, in: textView), CaptureScopeMap(theme: light).style(for: "keyword")?.foreground)
    }

    func testBurstOfEditsCoalescesIntoOneParse() async throws {
        let parser = FakeSyntaxParser(keywords: [])
        let (textView, _, highlighter) = makeEditor(text: "", parser: parser)
        await highlighter.waitForPendingParse()
        for character in "hello" {
            textView.insertText(String(character), replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
        }
        try await Task.sleep(for: .milliseconds(60))
        await highlighter.waitForPendingParse()
        XCTAssertEqual(parser.parseCount, 2)
        XCTAssertEqual((parser.receivedEdits.last ?? nil)?.count, 5)
    }

    func testReplaceTextForcesFullReparse() async throws {
        let parser = FakeSyntaxParser(keywords: ["let", "import"])
        let (textView, document, highlighter) = makeEditor(text: "let a = 1", parser: parser)
        await highlighter.waitForPendingParse()
        document.replaceText(with: "// c\nimport X", encoding: .utf8, lineEnding: .lf, modificationDate: nil)
        await highlighter.waitForPendingParse()
        XCTAssertEqual(parser.receivedEdits.last, .some(nil), "a wholesale replacement must not reuse the old tree")
        XCTAssertNil(foregroundColor(at: 0, in: textView), "'//' is not a keyword")
        XCTAssertEqual(foregroundColor(at: 5, in: textView), CaptureScopeMap(theme: theme).style(for: "keyword")?.foreground)
    }

    func testProgrammaticScrollPaintsNewViewportBeforeLayoutPass() async throws {
        let parser = FakeSyntaxParser(keywords: ["let"])
        let lines = (0..<2000).map { "let v\($0) = \($0)" }
        let text = lines.joined(separator: "\n")
        let (textView, document, highlighter) = makeEditor(text: text, parser: parser)
        highlighter.viewportMargin = 500
        await highlighter.waitForPendingParse()

        let end = document.textStorage.length
        let lastLineStart = end - (lines.last?.utf16.count ?? 0)
        XCTAssertNil(foregroundColor(at: lastLineStart, in: textView), "far end is not painted yet")

        textView.scrollRangeToVisible(NSRange(location: end, length: 0))
        highlighter.viewportDidChange()
        try await Task.sleep(for: .milliseconds(40)) // the async highlight pass runs before any layout pass
        XCTAssertEqual(foregroundColor(at: lastLineStart, in: textView), CaptureScopeMap(theme: theme).style(for: "keyword")?.foreground)
    }

    func testItalicAndBoldStylesBecomeFontsOnStorage() async throws {
        // A fake tree where "let" is a keyword; make the theme render keywords bold italic.
        var styled = theme!
        styled.tokenRules.append(TokenColorRule(scopes: ["keyword"], style: TokenStyle(foreground: nil, fontStyle: "bold italic")))
        let parser = FakeSyntaxParser(keywords: ["let"])
        let document = Quill.Document(url: nil, text: "let value = 42")
        let highlighter = SyntaxHighlighter(language: language, parser: parser, document: document, theme: styled)
        document.installHighlighterForTesting(highlighter)
        let scrollView = EditorView.makeScrollView(document: document, configuration: EditorConfiguration(), theme: styled)
        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        retainedScrollViews.append(scrollView)
        let textView = try XCTUnwrap(scrollView.documentView as? CodeTextView)
        await highlighter.waitForPendingParse()

        let base = EditorConfiguration().font
        let keywordFont = try XCTUnwrap(document.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let plainFont = try XCTUnwrap(document.textStorage.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(keywordFont.fontDescriptor.symbolicTraits.contains(.italic), "\(keywordFont)")
        XCTAssertTrue(keywordFont.fontDescriptor.symbolicTraits.contains(.bold), "\(keywordFont)")
        XCTAssertEqual(keywordFont.pointSize, base.pointSize)
        XCTAssertEqual(plainFont, base)
        XCTAssertFalse(document.isDirty, "font attributes are not edits")
        XCTAssertFalse(document.undoManager.canUndo)
        XCTAssertEqual(textView.typingAttributes[.font] as? NSFont, base, "typing stays in the base font")
        textView.setSelectedRange(NSRange(location: 2, length: 0)) // caret inside the italic run
        XCTAssertEqual(textView.typingAttributes[.font] as? NSFont, base, "caret moves must not pick up the italic font")
        textView.insertText("X", replacementRange: NSRange(location: 2, length: 0))
        let typedFont = document.textStorage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        XCTAssertEqual(typedFont, base, "typed text lands in the base font until the next pass")

        // Removing the style resets the font on the next pass.
        highlighter.theme = theme
        try await Task.sleep(for: .milliseconds(40))
        let resetFont = try XCTUnwrap(document.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(resetFont, base)
    }

    func testFontSizeChangeKeepsHighlights() async throws {
        let parser = FakeSyntaxParser(keywords: ["let"])
        let (textView, _, highlighter) = makeEditor(text: "let a = 1", parser: parser)
        await highlighter.waitForPendingParse()
        var configuration = EditorConfiguration()
        configuration.fontSize = 18
        textView.apply(configuration, theme: theme)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(foregroundColor(at: 0, in: textView), CaptureScopeMap(theme: theme).style(for: "keyword")?.foreground)
    }
}
