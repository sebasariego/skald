import AppKit

/// Keeps one document's syntax tree current and paints highlight colors onto the
/// attached text view's layout manager as rendering attributes. Nothing here touches
/// `NSTextStorage` attributes, so undo and edit processing stay untouched.
@MainActor
final class SyntaxHighlighter {
    let language: LanguageDefinition
    private let parser: any SyntaxParser
    private weak var document: Document?
    private weak var textView: CodeTextView?

    private var tree: (any SyntaxTree)?
    private var treeSnapshot: TextSnapshot?
    private var pendingEdits: [TextEdit] = []
    /// Set when the whole text was replaced; the next parse must not reuse the old tree.
    private var needsFullReparse = true
    private var parseTask: Task<Void, Never>?
    private var parseGeneration = 0
    private var highlightedRange: NSRange?
    private var highlightPassScheduled = false

    /// Base font and its bold/italic variants. Font changes are the one highlight that
    /// must live on the storage: TextKit 2 ignores font-like rendering attributes.
    private var fonts = StyledFonts(base: EditorConfiguration().font)
    private var hadStyledFonts = false
    var baseFont: NSFont {
        get { fonts.base }
        set {
            guard newValue != fonts.base else { return }
            fonts = StyledFonts(base: newValue)
            hadStyledFonts = false // the editor just reset every font to the new base
            highlightedRange = nil
            scheduleHighlightPass()
        }
    }

    private var scopeMap: CaptureScopeMap
    var theme: Theme {
        didSet {
            guard theme != oldValue else { return }
            scopeMap = CaptureScopeMap(theme: theme)
            highlightedRange = nil
            scheduleHighlightPass()
        }
    }

    /// Margin around the viewport, in UTF-16 units, so small scrolls never show bare text.
    var viewportMargin = 4000
    /// Delay before reparsing after an edit; coalesces bursts of typing.
    var reparseDelay: Duration = .milliseconds(12)

    init(language: LanguageDefinition, parser: any SyntaxParser, document: Document, theme: Theme) {
        self.language = language
        self.parser = parser
        self.document = document
        self.theme = theme
        self.scopeMap = CaptureScopeMap(theme: theme)
    }

    // MARK: Attachment

    /// Idempotent: re-attaching the same view is a no-op.
    func attach(_ view: CodeTextView) {
        guard textView !== view else { return }
        textView = view
        highlightedRange = nil
        if tree == nil {
            reparse(immediately: true)
        } else {
            scheduleHighlightPass()
        }
    }

    func detach(_ view: CodeTextView) {
        guard textView === view else { return }
        textView = nil
        highlightedRange = nil
    }

    // MARK: Document events

    func documentDidReplaceText() {
        pendingEdits = []
        needsFullReparse = true
        tree = nil
        treeSnapshot = nil
        highlightedRange = nil
        reparse(immediately: true)
    }

    /// Forces the next pass to repaint even if the viewport did not move.
    func invalidateHighlights() {
        highlightedRange = nil
        scheduleHighlightPass()
    }

    func documentDidChange(_ edit: TextEdit) {
        pendingEdits.append(edit)
        reparse(immediately: false)
    }

    /// Call when the visible range moved (scroll, resize, wrap change).
    func viewportDidChange() {
        scheduleHighlightPass()
    }

    // MARK: Parsing

    private func reparse(immediately: Bool) {
        parseTask?.cancel()
        parseGeneration += 1
        let generation = parseGeneration
        let delay = immediately ? Duration.zero : reparseDelay
        parseTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let self else { return }
            await self.runParse(generation: generation)
        }
    }

    private func runParse(generation: Int) async {
        guard let document else { return }
        let edits: [TextEdit]? = needsFullReparse ? nil : pendingEdits
        pendingEdits = []
        needsFullReparse = false
        let snapshot = document.snapshot()
        let result = await parser.parse(snapshot, edits: edits)
        // A newer parse was requested while this one ran; its result supersedes ours.
        guard generation == parseGeneration else { return }
        tree = result
        treeSnapshot = snapshot
        highlightedRange = nil
        highlightVisibleRange()
        // The window may still be settling its layout right after open; one more pass on the
        // next turn repaints if the viewport moved, and is a no-op otherwise.
        scheduleHighlightPass()
    }

    /// Waits for any in-flight parse. Tests use this; the app never needs to.
    func waitForPendingParse() async {
        await parseTask?.value
    }

    // MARK: Painting

    private func scheduleHighlightPass() {
        guard !highlightPassScheduled else { return }
        highlightPassScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.highlightPassScheduled = false
            self.highlightVisibleRange()
        }
    }

    private func highlightVisibleRange() {
        guard let textView, let tree, let treeSnapshot,
              let textLayoutManager = textView.textLayoutManager,
              let contentStorage = textView.textContentStorage else { return }

        let documentLength = contentStorage.textStorage?.length ?? 0
        let target = targetRange(in: textView, documentLength: min(documentLength, treeSnapshot.length))
        if let highlightedRange, NSEqualRanges(highlightedRange, target) { return }

        let spans = tree.highlights(in: target, text: treeSnapshot)
        let union = NSIntersectionRange(highlightedRange.map { NSUnionRange($0, target) } ?? target, NSRange(location: 0, length: documentLength))
        if let unionRange = textView.textRange(from: union) {
            textLayoutManager.removeRenderingAttribute(.foregroundColor, for: unionRange)
            textLayoutManager.removeRenderingAttribute(.underlineStyle, for: unionRange)
        }

        // Fonts go on the storage; reset the whole range first so stale italics vanish.
        var fontRuns: [(NSRange, NSFont)] = []
        for span in spans {
            let clipped = NSIntersectionRange(span.range, NSRange(location: 0, length: documentLength))
            guard clipped.length > 0, let textRange = textView.textRange(from: clipped) else { continue }
            if span.capture == "none" {
                // "@none" means: draw this range in the base color even inside a colored parent.
                textLayoutManager.removeRenderingAttribute(.foregroundColor, for: textRange)
                textLayoutManager.removeRenderingAttribute(.underlineStyle, for: textRange)
                fontRuns.append((clipped, fonts.base))
                continue
            }
            guard let style = scopeMap.style(for: span.capture) else { continue }
            if let color = style.foreground {
                textLayoutManager.addRenderingAttribute(.foregroundColor, value: color, for: textRange)
            }
            if style.underline {
                textLayoutManager.addRenderingAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, for: textRange)
            }
            if style.bold || style.italic {
                fontRuns.append((clipped, fonts.font(bold: style.bold, italic: style.italic)))
            }
        }
        let hasStyledFonts = fontRuns.contains { $0.1 != fonts.base }
        if hasStyledFonts || hadStyledFonts, let storage = contentStorage.textStorage, union.length > 0 {
            storage.beginEditing()
            storage.addAttribute(.font, value: fonts.base, range: union)
            for (range, font) in fontRuns where font != fonts.base {
                storage.addAttribute(.font, value: font, range: range)
            }
            storage.endEditing()
            // Typing continues in the base font; the next pass restyles what was typed.
            textView.typingAttributes[.font] = fonts.base
        }
        hadStyledFonts = hasStyledFonts
        highlightedRange = target

        // TextKit 2 bakes rendering attributes into line fragments at layout time. Fragments
        // laid out before this pass would keep their old colors in a layer-backed view until
        // something relaid them out, so invalidate the painted range explicitly.
        if let unionRange = textView.textRange(from: union) {
            textLayoutManager.invalidateLayout(for: unionRange)
        }
        textView.needsDisplay = true
    }

    /// Viewport plus margin, clamped to the document. The range comes from the view's
    /// current geometry, not `viewportRange`, which only updates during a layout pass
    /// and so lags one turn behind a programmatic scroll (Find Next, go to end).
    private func targetRange(in textView: CodeTextView, documentLength: Int) -> NSRange {
        guard let textLayoutManager = textView.textLayoutManager,
              let contentStorage = textView.textContentStorage else {
            return NSRange(location: 0, length: min(documentLength, viewportMargin))
        }
        let start = contentStorage.documentRange.location
        var viewport = NSRange(location: 0, length: min(documentLength, viewportMargin))

        let visibleRect = textView.visibleRect
        let inset = textView.textContainerInset
        if visibleRect.height > 0 {
            let rect = CGRect(x: 0, y: max(0, visibleRect.minY - inset.height), width: max(1, visibleRect.width), height: visibleRect.height)
            textLayoutManager.ensureLayout(for: rect)
            let top = textLayoutManager.textLayoutFragment(for: rect.origin)?.rangeInElement.location
            let bottom = textLayoutManager.textLayoutFragment(for: CGPoint(x: 0, y: rect.maxY))?.rangeInElement.endLocation
                ?? contentStorage.documentRange.endLocation
            if let top {
                let location = contentStorage.offset(from: start, to: top)
                let end = contentStorage.offset(from: start, to: bottom)
                viewport = NSRange(location: location, length: max(0, end - location))
            } else if let visible = textLayoutManager.textViewportLayoutController.viewportRange {
                let location = contentStorage.offset(from: start, to: visible.location)
                let end = contentStorage.offset(from: start, to: visible.endLocation)
                viewport = NSRange(location: location, length: max(0, end - location))
            }
        } else if let visible = textLayoutManager.textViewportLayoutController.viewportRange {
            let location = contentStorage.offset(from: start, to: visible.location)
            let end = contentStorage.offset(from: start, to: visible.endLocation)
            viewport = NSRange(location: location, length: max(0, end - location))
        }
        let lower = max(0, viewport.location - viewportMargin)
        let upper = min(documentLength, NSMaxRange(viewport) + viewportMargin)
        return NSRange(location: lower, length: max(0, upper - lower))
    }
}
