import XCTest
@testable import Skald

/// Renders the editor offscreen and checks that glyphs actually land on the bitmap.
@MainActor
final class EditorPixelTests: XCTestCase {
    private var retained: [NSScrollView] = []

    override func tearDown() {
        retained.removeAll()
    }

    static func nonBackgroundPixels(in scrollView: NSScrollView, background: NSColor, region: NSRect) -> Int {
        guard let bitmap = scrollView.bitmapImageRepForCachingDisplay(in: scrollView.bounds) else { return -1 }
        scrollView.cacheDisplay(in: scrollView.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / scrollView.bounds.width
        let bg = background.usingColorSpace(.sRGB) ?? background
        var count = 0
        for y in stride(from: Int(region.minY * scale), to: Int(region.maxY * scale), by: 2) {
            for x in stride(from: Int(region.minX * scale), to: Int(region.maxX * scale), by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let delta = abs(color.redComponent - bg.redComponent) + abs(color.greenComponent - bg.greenComponent) + abs(color.blueComponent - bg.blueComponent)
                if delta > 0.3 { count += 1 }
            }
        }
        return count
    }

    func testPlainTextIsVisible() throws {
        let theme = try ThemeLoader.load(from: TestResources.url("Skald/Resources/Themes/skald-dark.theme.json"))
        let document = Skald.Document(url: nil, text: "Hello, world. This is visible text.\nSecond line here.\n")
        let scrollView = EditorView.makeScrollView(document: document, configuration: EditorConfiguration(), theme: theme)
        retained.append(scrollView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(scrollView.documentView as? CodeTextView)
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        XCTAssertNotNil(textView.textLayoutManager)
        // Text area: right of the gutter, top 60 points. The gutter once painted over it.
        let textRegion = NSRect(x: 80, y: 0, width: 500, height: 60)
        let textPixels = Self.nonBackgroundPixels(in: scrollView, background: theme.colors.editorBackground, region: textRegion)
        XCTAssertGreaterThan(textPixels, 20, "no glyphs were drawn in the text area")
        // The gutter itself shows line numbers.
        let gutterRegion = NSRect(x: 0, y: 0, width: 44, height: 40)
        let gutterPixels = Self.nonBackgroundPixels(in: scrollView, background: theme.colors.editorBackground, region: gutterRegion)
        XCTAssertGreaterThan(gutterPixels, 5, "no line numbers were drawn in the gutter")
    }

    func testLongWrappedLinesStayVisible() throws {
        let theme = try ThemeLoader.load(from: TestResources.url("Skald/Resources/Themes/skald-light.theme.json"))
        let row = (0..<40).map { "column\($0)" }.joined(separator: ",")
        let document = Skald.Document(url: nil, text: Array(repeating: row, count: 5).joined(separator: "\n"))
        let scrollView = EditorView.makeScrollView(document: document, configuration: EditorConfiguration(), theme: theme)
        retained.append(scrollView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(scrollView.documentView as? CodeTextView)
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        let pixels = Self.nonBackgroundPixels(in: scrollView, background: theme.colors.editorBackground, region: NSRect(x: 80, y: 0, width: 500, height: 200))
        XCTAssertGreaterThan(pixels, 200, "wrapped CSV rows must be drawn")
    }
}
