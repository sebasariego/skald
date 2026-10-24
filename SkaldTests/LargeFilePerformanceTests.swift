import XCTest
@testable import Skald

/// Opens a generated ~5 MB file and renders the first screen. The 300 ms budget is the
/// product requirement and applies to optimized builds; debug builds get more slack so
/// the test still catches regressions without failing on every Debug run.
@MainActor
final class LargeFilePerformanceTests: XCTestCase {
    static let budget: Duration = {
        #if DEBUG
        return .milliseconds(1500)
        #else
        return .milliseconds(300)
        #endif
    }()

    private var retained: [NSScrollView] = []

    override func tearDown() {
        retained.removeAll()
    }

    nonisolated static func makeLargeSource(targetBytes: Int) -> String {
        let snippet = """
        import Foundation

        /// A generated type used only to stress the editor.
        struct Sample%d: Codable, Equatable {
            let identifier: Int
            var name: String
            var values: [Double]

            func total() -> Double {
                values.reduce(0) { $0 + $1 } * Double(identifier % 7)
            }

            mutating func rename(to newName: String) {
                guard !newName.isEmpty else { return }
                name = newName
            }
        }

        """
        var text = ""
        text.reserveCapacity(targetBytes + snippet.count)
        var index = 0
        while text.utf8.count < targetBytes {
            text += snippet.replacingOccurrences(of: "%d", with: String(index))
            index += 1
        }
        return text
    }

    func testOpensAndRendersFiveMegabytesWithinBudget() async throws {
        let directory = try TestTemporaryDirectory()
        defer { directory.remove() }
        let text = Self.makeLargeSource(targetBytes: 5 * 1024 * 1024)
        let url = try directory.file("Large.swift", contents: Data(text.utf8))
        XCTAssertGreaterThanOrEqual(text.utf8.count, 5 * 1024 * 1024)

        let store = DocumentStore()
        let clock = ContinuousClock()
        let start = clock.now

        let document = try await store.open(url)
        let opened = clock.now
        let scrollView = EditorView.makeScrollView(document: document, configuration: EditorConfiguration(), theme: ThemeLoader.fallbackTheme)
        retained.append(scrollView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        scrollView.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(scrollView.documentView as? CodeTextView)
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        let bitmap = try XCTUnwrap(scrollView.bitmapImageRepForCachingDisplay(in: scrollView.bounds))
        scrollView.cacheDisplay(in: scrollView.bounds, to: bitmap)
        let rendered = clock.now

        let total = rendered - start
        print("PERF open=\(opened - start) view+render=\(rendered - opened) total=\(total) lines=\(document.lineIndex.lineCount)")
        XCTAssertLessThan(total, Self.budget, "open + first render took \(total)")
        XCTAssertGreaterThan(document.lineIndex.lineCount, 100_000)
        XCTAssertNotNil(textView.textLayoutManager)
    }

    func testRenderingTheEndOfFiveMegabytesWithinBudget() async throws {
        let text = Self.makeLargeSource(targetBytes: 5 * 1024 * 1024)
        let document = Skald.Document(url: nil, text: text)
        let scrollView = EditorView.makeScrollView(document: document, configuration: EditorConfiguration(), theme: ThemeLoader.fallbackTheme)
        retained.append(scrollView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        scrollView.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(scrollView.documentView as? CodeTextView)

        let clock = ContinuousClock()
        let start = clock.now
        let end = document.textStorage.length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.scrollRangeToVisible(NSRange(location: end, length: 0))
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        let bitmap = try XCTUnwrap(scrollView.bitmapImageRepForCachingDisplay(in: scrollView.bounds))
        scrollView.cacheDisplay(in: scrollView.bounds, to: bitmap)
        let elapsed = clock.now - start
        print("PERF scroll-to-end + render: \(elapsed)")
        XCTAssertLessThan(elapsed, Self.budget, "scrolling to the end and rendering took \(elapsed)")
        XCTAssertGreaterThan(scrollView.contentView.bounds.minY, 0, "the view did scroll")
        XCTAssertNotNil(textView.textLayoutManager)
    }

    /// Every snippet in the fixture has a doc comment, so each highlight pass also rewrites
    /// font runs on the storage. Scrolling must stay cheap regardless.
    func testScrollingThroughHighlightedLargeFile() async throws {
        TreeSitterSupport.install(queryDirectory: TestResources.url("Skald/Resources/Queries"))
        defer { LanguageRegistry.parserFactory = nil }
        let directory = try TestTemporaryDirectory()
        defer { directory.remove() }
        let url = try directory.file("Scroll.swift", contents: Data(Self.makeLargeSource(targetBytes: 5 * 1024 * 1024).utf8))
        let theme = try ThemeLoader.load(from: TestResources.url("Skald/Resources/Themes/skald-dark.theme.json"))
        let store = DocumentStore()
        store.theme = theme
        let document = try await store.open(url)
        let highlighter = try XCTUnwrap(document.highlighter)
        let scrollView = EditorView.makeScrollView(document: document, configuration: EditorConfiguration(), theme: theme)
        retained.append(scrollView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        scrollView.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(scrollView.documentView as? CodeTextView)
        await highlighter.waitForPendingParse()

        let clock = ContinuousClock()
        var total: Duration = .zero
        let steps = 20
        for step in 1...steps {
            let location = min(document.textStorage.length - 1, step * 12_000)
            let start = clock.now
            textView.scrollRangeToVisible(NSRange(location: location, length: 0))
            highlighter.viewportDidChange()
            try await Task.sleep(for: .milliseconds(1)) // lets the coalesced highlight pass run
            textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
            total += clock.now - start
        }
        let perStep = total / steps
        // Measured 11 ms optimized, of which the font-run storage write is about 0.6 ms;
        // the rest is laying out a fresh screen after a 12k-character jump.
        print("PERF scroll step with highlight + font runs: \(perStep) average over \(steps)")
        #if DEBUG
        XCTAssertLessThan(perStep, .milliseconds(100))
        #else
        XCTAssertLessThan(perStep, .milliseconds(30))
        #endif
    }

    func testTypingInLargeFileStaysResponsive() async throws {
        let text = Self.makeLargeSource(targetBytes: 5 * 1024 * 1024)
        let document = Skald.Document(url: nil, text: text)
        let scrollView = EditorView.makeScrollView(document: document, configuration: EditorConfiguration(), theme: ThemeLoader.fallbackTheme)
        retained.append(scrollView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        scrollView.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(scrollView.documentView as? CodeTextView)
        textView.setSelectedRange(NSRange(location: 200, length: 0))

        let clock = ContinuousClock()
        let start = clock.now
        for character in "let inserted = 42\n" {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
        }
        textView.insertNewline(nil)
        let elapsed = clock.now - start
        print("PERF 19 keystrokes in 5 MB file: \(elapsed)")
        #if DEBUG
        XCTAssertLessThan(elapsed, .milliseconds(1500))
        #else
        XCTAssertLessThan(elapsed, .milliseconds(300))
        #endif
    }
}
