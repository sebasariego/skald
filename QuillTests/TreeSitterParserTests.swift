import XCTest
@testable import Quill

/// Exercises the real grammars and the queries that ship with them.
final class TreeSitterParserTests: XCTestCase {
    private let queryDirectory = TestResources.url("Quill/Resources/Queries")

    private func parser(_ id: String) throws -> any SyntaxParser {
        let language = try XCTUnwrap(LanguageRegistry.language(withID: id))
        return try XCTUnwrap(TreeSitterSupport.makeParser(for: language, queryDirectory: queryDirectory), "no parser for \(id)")
    }

    private func spans(_ id: String, _ source: String) async throws -> [HighlightSpan] {
        let snapshot = TextSnapshot(source)
        let tree = try await parser(id).parse(snapshot, edits: [])
        return tree.highlights(in: NSRange(location: 0, length: snapshot.length), text: snapshot)
    }

    private func captures(_ spans: [HighlightSpan], in source: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for span in spans {
            let text = (source as NSString).substring(with: span.range)
            result[span.capture, default: []].append(text)
        }
        return result
    }

    func testEveryRegisteredLanguageCompilesItsQuery() {
        for language in LanguageRegistry.all {
            XCTAssertNotNil(TreeSitterSupport.makeParser(for: language, queryDirectory: queryDirectory), "query failed for \(language.id)")
        }
    }

    func testSwiftHighlights() async throws {
        let source = "import Foundation\nlet count = 42 // answer\nfunc go() -> String { return \"hi\" }\n"
        let found = captures(try await spans("swift", source), in: source)
        XCTAssertTrue(found["keyword"]?.contains("let") ?? false, "\(found)")
        XCTAssertTrue(found["keyword.import"]?.contains("import") ?? false, "\(found)")
        XCTAssertEqual(found["number"], ["42"])
        XCTAssertEqual(found["comment"], ["// answer"])
        XCTAssertTrue(found["string"]?.contains("hi") ?? false, "string text is captured apart from its quotes: \(found)")
        XCTAssertTrue(found["type"]?.contains("String") ?? false, "\(found)")
    }

    func testPythonPredicatesDistinguishConstants() async throws {
        let source = "LIMIT = 10\nvalue = LIMIT\ndef run(x):\n    return print(x)\n"
        let found = captures(try await spans("python", source), in: source)
        XCTAssertTrue(found["constant"]?.contains("LIMIT") ?? false, "\(found)")
        XCTAssertFalse(found["constant"]?.contains("value") ?? false, "\(found)")
        XCTAssertTrue(found["function.builtin"]?.contains("print") ?? false, "\(found)")
        XCTAssertTrue(found["keyword"]?.contains("def") ?? false, "\(found)")
    }

    func testJSONYAMLAndMarkdown() async throws {
        let json = "{\"name\": \"quill\", \"count\": 3, \"ok\": true}"
        let jsonFound = captures(try await spans("json", json), in: json)
        XCTAssertEqual(jsonFound["string.special.key"], ["\"name\"", "\"count\"", "\"ok\""])
        XCTAssertEqual(jsonFound["number"], ["3"])

        let yaml = "name: quill\ncount: 3\n# note\n"
        let yamlFound = captures(try await spans("yaml", yaml), in: yaml)
        XCTAssertTrue(yamlFound["property"]?.contains("name") ?? false, "\(yamlFound)")
        XCTAssertEqual(yamlFound["comment"], ["# note"])

        let markdown = "# Title\n\nSome text.\n\n```swift\nlet a = 1\n```\n"
        let markdownFound = captures(try await spans("markdown", markdown), in: markdown)
        XCTAssertTrue(markdownFound["text.title"]?.first?.contains("Title") ?? false, "\(markdownFound)")
    }

    func testBashHighlights() async throws {
        let source = "#!/bin/zsh\nif [ -f \"$HOME/x\" ]; then\n  echo hello # note\nfi\n"
        let found = captures(try await spans("bash", source), in: source)
        XCTAssertTrue(found["keyword"]?.contains("if") ?? false, "\(found)")
        XCTAssertTrue(found["comment"]?.contains("# note") ?? false, "\(found)")
        XCTAssertTrue(found["function"]?.contains("echo") ?? false, "\(found)")
        XCTAssertTrue((found["property"] ?? []).contains("HOME") || (found["variable"] ?? []).contains("HOME"), "\(found)")
    }

    func testHTMLInjectsJavaScriptAndCSS() async throws {
        let source = "<html><head><style>body { color: red; }</style></head>\n<body class=\"a\"><script>let x = 1;</script></body></html>\n"
        let found = captures(try await spans("html", source), in: source)
        XCTAssertTrue(found["tag"]?.contains("body") ?? false, "\(found)")
        XCTAssertTrue(found["attribute"]?.contains("class") ?? false, "\(found)")
        XCTAssertTrue(found["keyword"]?.contains("let") ?? false, "javascript inside <script>: \(found)")
        XCTAssertTrue(found["property"]?.contains("color") ?? false, "css inside <style>: \(found)")
    }

    func testXMLAndSVG() async throws {
        let source = "<?xml version=\"1.0\"?>\n<svg width=\"10\"><!-- c --><rect x=\"1\"/></svg>\n"
        let found = captures(try await spans("xml", source), in: source)
        XCTAssertTrue(found["tag"]?.contains("svg") ?? false, "\(found)")
        XCTAssertTrue((found["attribute"] ?? found["property"])?.contains("width") ?? false, "\(found)")
        XCTAssertTrue(found["comment"]?.contains("<!-- c -->") ?? false, "\(found)")
        XCTAssertEqual(LanguageRegistry.language(for: URL(fileURLWithPath: "/tmp/icon.svg"))?.id, "xml")
    }

    func testJavaScriptWithJSX() async throws {
        let source = "import React from 'react';\nexport function App({ name }) {\n  const n = 42; // hi\n  return <div className=\"x\">{name}</div>;\n}\n"
        let found = captures(try await spans("javascript", source), in: source)
        XCTAssertTrue(found["keyword"]?.contains("import") ?? false, "\(found)")
        XCTAssertTrue((found["function"] ?? []).contains("App") || (found["constructor"] ?? []).contains("App"), "\(found)")
        XCTAssertEqual(found["number"], ["42"])
        XCTAssertEqual(found["comment"], ["// hi"])
        XCTAssertTrue(found["tag"]?.contains("div") ?? false, "jsx tags: \(found)")
        XCTAssertEqual(LanguageRegistry.language(for: URL(fileURLWithPath: "/tmp/a.jsx"))?.id, "javascript")
    }

    func testTypeScriptAndTSX() async throws {
        let ts = "interface User { id: number; name?: string }\nconst greet = (u: User): string => `hi ${u.name}`;\n"
        let found = captures(try await spans("typescript", ts), in: ts)
        XCTAssertTrue(found["keyword"]?.contains("interface") ?? false, "\(found)")
        XCTAssertTrue(found["type"]?.contains("User") ?? false, "\(found)")
        XCTAssertTrue(found["type.builtin"]?.contains("number") ?? false, "\(found)")
        XCTAssertTrue(found["string"]?.contains("`hi ${u.name}`") ?? false, "\(found)")

        let tsx = "export const C = (p: { title: string }) => <h1 id=\"t\">{p.title}</h1>;\n"
        let foundTSX = captures(try await spans("tsx", tsx), in: tsx)
        XCTAssertTrue(foundTSX["tag"]?.contains("h1") ?? false, "\(foundTSX)")
        XCTAssertTrue(foundTSX["type.builtin"]?.contains("string") ?? false, "\(foundTSX)")
    }

    func testCSS() async throws {
        let source = ".card > a:hover { color: #fff; margin: 4px 0; }\n"
        let found = captures(try await spans("css", source), in: source)
        XCTAssertTrue(found["property"]?.contains("color") ?? false, "\(found)")
        XCTAssertTrue(found["tag"]?.contains("a") ?? false, "\(found)")
        XCTAssertEqual(found["string.special"], ["#fff"], "\(found)")
        XCTAssertTrue(found["number"]?.contains("4px") ?? false, "\(found)")
    }

    func testMarkdownInjectsInlineAndFencedCode() async throws {
        let source = "# Title\n\nSome *soft* and **loud** text with `code`.\n\n```swift\nlet a = 1\n```\n\n```python\ndef f(): pass\n```\n"
        let found = captures(try await spans("markdown", source), in: source)
        XCTAssertEqual(found["text.emphasis"], ["*soft*"], "\(found)")
        XCTAssertEqual(found["text.strong"], ["**loud**"], "\(found)")
        XCTAssertTrue(found["text.literal"]?.contains("`code`") ?? false, "\(found)")
        XCTAssertTrue(found["none"]?.contains("let a = 1\n") ?? false, "fence content is cleared before the injected grammar colors it: \(found)")
        XCTAssertTrue(found["keyword"]?.contains("let") ?? false, "swift inside a fence: \(found)")
        XCTAssertTrue(found["keyword"]?.contains("def") ?? false, "python inside a fence: \(found)")
        XCTAssertTrue(found["text.title"]?.first?.contains("Title") ?? false, "\(found)")
    }

    func testInjectedLayersSurviveIncrementalEdits() async throws {
        let parser = try parser("markdown")
        let first = TextSnapshot("Plain *a* text\n")
        _ = await parser.parse(first, edits: [])
        // Insert "**b** " at offset 6 (just before "*a*").
        let second = TextSnapshot("Plain **b** *a* text\n")
        let edit = TextEdit(
            startOffset: 6, oldEndOffset: 6, newEndOffset: 12,
            startPoint: TextPoint(row: 0, column: 6), oldEndPoint: TextPoint(row: 0, column: 6), newEndPoint: TextPoint(row: 0, column: 12)
        )
        let tree = await parser.parse(second, edits: [edit])
        let found = captures(tree.highlights(in: NSRange(location: 0, length: second.length), text: second), in: second.string as String)
        XCTAssertEqual(found["text.strong"], ["**b**"], "\(found)")
        XCTAssertEqual(found["text.emphasis"], ["*a*"], "\(found)")
    }

    func testMarkdownFullReparseRebuildsInjectionLayers() async throws {
        let parser = try parser("markdown")
        let withFence = TextSnapshot("Text\n\n```swift\nlet a = 1\n```\n")
        let before = await parser.parse(withFence, edits: [])
        let found = captures(before.highlights(in: NSRange(location: 0, length: withFence.length), text: withFence), in: withFence.string as String)
        XCTAssertTrue(found["keyword"]?.contains("let") ?? false, "\(found)")

        // Wholesale replacement with no fence: the swift layer must go away without a crash.
        let plain = TextSnapshot("Just *text* now\n")
        let after = await parser.parse(plain, edits: nil)
        let foundAfter = captures(after.highlights(in: NSRange(location: 0, length: plain.length), text: plain), in: plain.string as String)
        XCTAssertNil(foundAfter["keyword"])
        XCTAssertEqual(foundAfter["text.emphasis"], ["*text*"], "\(foundAfter)")

        // And back again, still via a full reparse.
        let again = await parser.parse(withFence, edits: nil)
        let foundAgain = captures(again.highlights(in: NSRange(location: 0, length: withFence.length), text: withFence), in: withFence.string as String)
        XCTAssertTrue(foundAgain["keyword"]?.contains("let") ?? false, "\(foundAgain)")
    }

    func testIncrementalReparseAfterEdit() async throws {
        let parser = try parser("swift")
        let first = TextSnapshot("let a = 1\n")
        _ = await parser.parse(first, edits: [])

        // Insert a comment line at the top.
        let inserted = "// note\n"
        let second = TextSnapshot(inserted + "let a = 1\n")
        let edit = TextEdit(
            startOffset: 0, oldEndOffset: 0, newEndOffset: inserted.utf16.count,
            startPoint: TextPoint(row: 0, column: 0), oldEndPoint: TextPoint(row: 0, column: 0), newEndPoint: TextPoint(row: 1, column: 0)
        )
        let tree = await parser.parse(second, edits: [edit])
        let found = captures(tree.highlights(in: NSRange(location: 0, length: second.length), text: second), in: second.string as String)
        XCTAssertEqual(found["comment"], ["// note"])
        XCTAssertTrue(found["keyword"]?.contains("let") ?? false)
    }

    func testNilEditsDiscardTheOldTree() async throws {
        let parser = try parser("swift")
        _ = await parser.parse(TextSnapshot("let a = 1"), edits: [])
        let replaced = TextSnapshot("// c\nimport X")
        let tree = await parser.parse(replaced, edits: nil)
        let found = captures(tree.highlights(in: NSRange(location: 0, length: replaced.length), text: replaced), in: replaced.string as String)
        XCTAssertEqual(found["comment"], ["// c"])
        XCTAssertNil(found["keyword"]?.first(where: { $0 == "let" }))
        XCTAssertTrue(found["keyword.import"]?.contains("import") ?? false, "\(found)")
    }

    func testRangeLimitsQueryToViewport() async throws {
        let source = (0..<200).map { "let v\($0) = \($0)" }.joined(separator: "\n")
        let snapshot = TextSnapshot(source)
        let tree = try await parser("swift").parse(snapshot, edits: [])
        let window = NSRange(location: 1000, length: 300)
        let found = tree.highlights(in: window, text: snapshot)
        XCTAssertFalse(found.isEmpty)
        for span in found {
            XCTAssertTrue(NSIntersectionRange(span.range, window).length > 0, "span \(span) outside \(window)")
        }
    }

    @MainActor
    func testHighlighterPaintsRealSwift() async throws {
        TreeSitterSupport.install(queryDirectory: queryDirectory)
        defer { LanguageRegistry.parserFactory = nil }
        let directory = try TestTemporaryDirectory()
        defer { directory.remove() }
        let url = try directory.file("Real.swift", contents: Data("let real = true\n".utf8))
        let theme = try ThemeLoader.load(from: TestResources.url("Quill/Resources/Themes/quill-dark.theme.json"))
        let store = DocumentStore()
        store.theme = theme
        let document = try await store.open(url)
        let highlighter = try XCTUnwrap(document.highlighter)
        let scrollView = EditorView.makeScrollView(document: document, configuration: EditorConfiguration(), theme: theme)
        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        await highlighter.waitForPendingParse()
        let textView = try XCTUnwrap(scrollView.documentView as? CodeTextView)
        let contentStorage = try XCTUnwrap(textView.textContentStorage)
        let location = try XCTUnwrap(contentStorage.location(contentStorage.documentRange.location, offsetBy: 0))
        var color: NSColor?
        textView.textLayoutManager?.enumerateRenderingAttributes(from: location, reverse: false) { _, attributes, range in
            if range.contains(location) { color = attributes[.foregroundColor] as? NSColor }
            return false
        }
        XCTAssertEqual(color, CaptureScopeMap(theme: theme).style(for: "keyword")?.foreground)
        withExtendedLifetime(scrollView) {}
    }

    func testParsesFiveMegabytesOffMainInReasonableTime() async throws {
        let source = LargeFilePerformanceTests.makeLargeSource(targetBytes: 5 * 1024 * 1024)
        let snapshot = TextSnapshot(source)
        let parser = try parser("swift")
        let clock = ContinuousClock()
        let start = clock.now
        let tree = await parser.parse(snapshot, edits: [])
        let parsed = clock.now
        let found = tree.highlights(in: NSRange(location: 0, length: 4000), text: snapshot)
        let queried = clock.now
        print("PERF tree-sitter 5 MB swift parse=\(parsed - start) viewport query=\(queried - parsed) spans=\(found.count)")
        XCTAssertFalse(found.isEmpty)
        XCTAssertLessThan(queried - parsed, .milliseconds(50), "viewport query must be cheap")
        XCTAssertLessThan(parsed - start, .seconds(20))

        // One keystroke near the top: the incremental reparse must reuse the old tree.
        let inserted = "x"
        let edited = TextSnapshot((source as NSString).replacingCharacters(in: NSRange(location: 30, length: 0), with: inserted))
        let edit = TextEdit(
            startOffset: 30, oldEndOffset: 30, newEndOffset: 31,
            startPoint: TextPoint(row: 2, column: 11), oldEndPoint: TextPoint(row: 2, column: 11), newEndPoint: TextPoint(row: 2, column: 12)
        )
        let editStart = clock.now
        let reparsed = await parser.parse(edited, edits: [edit])
        let editDone = clock.now
        let after = reparsed.highlights(in: NSRange(location: 0, length: 4000), text: edited)
        print("PERF tree-sitter incremental reparse after 1 edit=\(editDone - editStart)")
        XCTAssertFalse(after.isEmpty)
        XCTAssertLessThan(editDone - editStart, .milliseconds(250), "incremental reparse should be far cheaper than a full parse")
    }
}
