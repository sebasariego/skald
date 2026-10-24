import XCTest
@testable import Skald

@MainActor
/// Regression guard: text drawn before the first highlight pass must be recolored by it.
/// TextKit 2 bakes rendering attributes into line fragments at layout time, so the pass
/// has to invalidate layout for the range it painted.
final class FirstPaintHighlightTests: XCTestCase {
    private var retained: [NSScrollView] = []
    override func tearDown() { retained.removeAll() }

    /// Pixels in `region` close to `target` color.
    static func pixels(matching target: NSColor, in scrollView: NSScrollView, region: NSRect) -> Int {
        guard let bitmap = scrollView.bitmapImageRepForCachingDisplay(in: scrollView.bounds) else { return -1 }
        scrollView.cacheDisplay(in: scrollView.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / scrollView.bounds.width
        let t = target.usingColorSpace(.sRGB) ?? target
        var count = 0
        for y in stride(from: Int(region.minY * scale), to: Int(region.maxY * scale), by: 1) {
            for x in stride(from: Int(region.minX * scale), to: Int(region.maxX * scale), by: 1) {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let d = abs(c.redComponent - t.redComponent) + abs(c.greenComponent - t.greenComponent) + abs(c.blueComponent - t.blueComponent)
                if d < 0.25 { count += 1 }
            }
        }
        return count
    }

    func testColorsAppearOnTextLaidOutBeforeTheFirstPass() async throws {
        TreeSitterSupport.install(queryDirectory: TestResources.url("Skald/Resources/Queries"))
        defer { LanguageRegistry.parserFactory = nil }
        let directory = try TestTemporaryDirectory()
        defer { directory.remove() }
        // A doc comment at the top makes the pass write italic font runs to the storage.
        let source = (["/// Documented module.", "/// Second line of the comment."] + (0..<40).map { "let value\($0) = \($0)" }).joined(separator: "\n")
        let url = try directory.file("Plain.swift", contents: Data(source.utf8))
        let theme = try ThemeLoader.load(from: TestResources.url("Skald/Resources/Themes/skald-dark.theme.json"))
        let keywordColor = try XCTUnwrap(CaptureScopeMap(theme: theme).style(for: "keyword")?.foreground)

        // Hold the parser back so the view lays out and draws before any highlight exists.
        let gate = GatedParserFactory(queryDirectory: TestResources.url("Skald/Resources/Queries"))
        LanguageRegistry.parserFactory = { gate.make($0) }
        let store = DocumentStore()
        store.theme = theme
        let document = try await store.open(url)
        let highlighter = try XCTUnwrap(document.highlighter)
        let scrollView = EditorView.makeScrollView(document: document, configuration: EditorConfiguration(), theme: theme)
        retained.append(scrollView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        let region = NSRect(x: 60, y: 0, width: 700, height: 580)
        let before = Self.pixels(matching: keywordColor, in: scrollView, region: region)

        gate.open()
        await highlighter.waitForPendingParse()
        try await Task.sleep(for: .milliseconds(50))
        let after = Self.pixels(matching: keywordColor, in: scrollView, region: region)
        let textView = try XCTUnwrap(scrollView.documentView as? CodeTextView)
        let firstLet = (source as NSString).range(of: "let value0").location
        var attribute: NSColor?
        if let cs = textView.textContentStorage, let loc = cs.location(cs.documentRange.location, offsetBy: firstLet) {
            textView.textLayoutManager?.enumerateRenderingAttributes(from: loc, reverse: false) { _, attrs, range in
                if range.contains(loc) { attribute = attrs[.foregroundColor] as? NSColor }
                return false
            }
        }
        XCTAssertNotNil(attribute, "rendering attribute missing on the first keyword")
        XCTAssertEqual(before, 0)
        XCTAssertGreaterThan(after, 100, "text laid out before the pass must be redrawn in color")
    }
}

/// Wraps the real parser so a test can decide when the first parse may finish.
final class GatedParserFactory: @unchecked Sendable {
    private let queryDirectory: URL
    private let semaphore = AsyncGate()
    init(queryDirectory: URL) { self.queryDirectory = queryDirectory }
    func make(_ language: LanguageDefinition) -> (any SyntaxParser)? {
        guard let real = TreeSitterSupport.makeParser(for: language, queryDirectory: queryDirectory) else { return nil }
        return GatedParser(real: real, gate: semaphore)
    }
    func open() { semaphore.open() }
}

final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func open() {
        lock.lock(); isOpen = true; let w = waiters; waiters = []; lock.unlock()
        w.forEach { $0.resume() }
    }
    func wait() async {
        lock.lock()
        if isOpen { lock.unlock(); return }
        await withCheckedContinuation { c in waiters.append(c); lock.unlock() }
    }
}

struct GatedParser: SyntaxParser {
    let real: any SyntaxParser
    let gate: AsyncGate
    func parse(_ text: TextSnapshot, edits: [TextEdit]?) async -> any SyntaxTree {
        await gate.wait()
        return await real.parse(text, edits: edits)
    }
}
