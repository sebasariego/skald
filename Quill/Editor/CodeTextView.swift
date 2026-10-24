import AppKit

/// The editor surface. TextKit 2 only: never touch `layoutManager` on this class or
/// AppKit silently falls back to TextKit 1 for the whole view.
final class CodeTextView: NSTextView {
    let document: Document
    private(set) var configuration = EditorConfiguration()
    private(set) var theme = ThemeLoader.fallbackTheme
    weak var gutter: GutterView?
    /// Reports the selection after every change; the status bar listens.
    var onSelectionChange: ((NSRange) -> Void)?

    private var bracketPair: BracketMatcher.Pair?
    /// Sorted match ranges from the find bar; drawn behind the text.
    var searchMatches: [NSRange] = [] { didSet { needsDisplay = true } }
    var currentSearchMatch: NSRange? { didSet { needsDisplay = true } }
    private var viewportObserver: NSObjectProtocol?
    private var viewportPassScheduled = false

    deinit {
        if let viewportObserver {
            NotificationCenter.default.removeObserver(viewportObserver)
        }
    }

    init(document: Document) {
        self.document = document

        let contentStorage = NSTextContentStorage()
        contentStorage.textStorage = document.textStorage
        let textLayoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(textLayoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        textLayoutManager.textContainer = container

        super.init(frame: .zero, textContainer: container)
        configureBehavior()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            document.highlighter?.detach(self)
        }
    }

    /// Called by `EditorView` once the scroll view exists.
    func didAttachToScrollView(_ scrollView: NSScrollView) {
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        viewportObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clipView, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewportDidChange() }
        }
        document.highlighter?.attach(self)
    }

    private func viewportDidChange() {
        gutter?.needsDisplay = true
        document.highlighter?.viewportDidChange()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// The document's undo stack, so undo survives tab switches.
    override var undoManager: UndoManager? {
        document.undoManager
    }

    private var storageText: NSString {
        document.textStorage.mutableString
    }

    // MARK: Configuration

    private func configureBehavior() {
        isRichText = false
        allowsUndo = true
        usesFontPanel = false
        usesFindBar = false
        usesInspectorBar = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        importsGraphics = false
        allowsImageEditing = false

        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainerInset = NSSize(width: 6, height: 8)

        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textColor = .labelColor
        insertionPointColor = .labelColor
    }

    func apply(_ configuration: EditorConfiguration, theme: Theme? = nil) {
        let previous = self.configuration
        let previousTheme = self.theme
        self.configuration = configuration
        if let theme { self.theme = theme }
        let themeChanged = previousTheme != self.theme
        let needsAttributes = typingAttributes[.font] == nil
            || previous.font != configuration.font
            || previous.tabWidth != configuration.tabWidth
            || themeChanged
        if needsAttributes {
            applyBaseAttributes()
        }
        if themeChanged || typingAttributes[.font] == nil {
            applyThemeColors()
        }
        if previous.softWrap != configuration.softWrap || !didConfigureWrap {
            setSoftWrap(configuration.softWrap)
            document.highlighter?.viewportDidChange()
        }
        gutter?.apply(configuration, theme: self.theme)
        // A highlighter can appear after the view exists (Save As to a known extension).
        if superview != nil {
            document.highlighter?.attach(self)
        }
        document.highlighter?.baseFont = configuration.font
        if needsAttributes {
            // Storage attribute edits can drop rendering attributes; repaint regardless of scroll.
            document.highlighter?.invalidateHighlights()
        }
        needsDisplay = true
    }

    private func applyBaseAttributes() {
        var attributes = configuration.baseAttributes
        attributes[.foregroundColor] = theme.colors.editorForeground
        font = configuration.font
        typingAttributes = attributes
        let storage = document.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttributes(attributes, range: fullRange)
        storage.endEditing()
    }

    private func applyThemeColors() {
        let colors = theme.colors
        backgroundColor = colors.editorBackground
        enclosingScrollView?.backgroundColor = colors.editorBackground
        textColor = colors.editorForeground
        insertionPointColor = colors.cursor
        selectedTextAttributes = [.backgroundColor: colors.selectionBackground]
    }

    private var didConfigureWrap = false

    private func setSoftWrap(_ wrap: Bool) {
        didConfigureWrap = true
        guard let container = textContainer else { return }
        let scrollView = enclosingScrollView
        if wrap {
            container.widthTracksTextView = true
            container.size = NSSize(width: scrollView?.contentSize.width ?? bounds.width, height: CGFloat.greatestFiniteMagnitude)
            isHorizontallyResizable = false
            autoresizingMask = [.width]
            if let scrollView {
                frame.size.width = scrollView.contentSize.width
            }
            scrollView?.hasHorizontalScroller = false
        } else {
            container.widthTracksTextView = false
            container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            isHorizontallyResizable = true
            autoresizingMask = []
            scrollView?.hasHorizontalScroller = true
        }
        textLayoutManager?.textViewportLayoutController.layoutViewport()
    }

    // MARK: Change tracking

    override func didChangeText() {
        super.didChangeText()
        gutter?.updateThickness()
        gutter?.needsDisplay = true
        refreshBracketPair()
        onSelectionChange?(selectedRange())
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        // AppKit derives typing attributes from the character before the caret; inside an
        // italic comment that would make new text italic. Always type in the base font.
        if typingAttributes[.font] as? NSFont != configuration.font {
            typingAttributes[.font] = configuration.font
        }
        gutter?.needsDisplay = true
        refreshBracketPair()
        needsDisplay = true
        onSelectionChange?(selectedRange())
    }

    private func refreshBracketPair() {
        let selection = selectedRange()
        guard selection.length == 0 else {
            bracketPair = nil
            return
        }
        bracketPair = BracketMatcher.pair(adjacentTo: selection.location, in: storageText)
    }

    // MARK: Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if configuration.highlightCurrentLine, selectedRange().length == 0, window?.firstResponder === self || window == nil {
            drawCurrentLineHighlight(in: rect)
        }
        drawSearchMatches(in: rect)
        if let bracketPair {
            theme.colors.bracketMatchBackground.setFill()
            for index in [bracketPair.open, bracketPair.close] {
                for frame in segmentFrames(for: NSRange(location: index, length: 1)) where frame.intersects(rect) {
                    NSBezierPath(roundedRect: frame.insetBy(dx: -1, dy: 0), xRadius: 2, yRadius: 2).fill()
                }
            }
        }
    }

    private func drawSearchMatches(in rect: NSRect) {
        guard !searchMatches.isEmpty else { return }
        let visible = visibleCharacterRange()
        guard visible.length > 0 else { return }
        // Matches are sorted, so jump to the first one that can intersect the visible text.
        var index = TextSearcher.indexOfMatch(atOrAfter: max(0, visible.location - 1), in: searchMatches) ?? 0
        if searchMatches[index].location < visible.location - 1 { index = 0 }
        while index < searchMatches.count, searchMatches[index].location < NSMaxRange(visible) {
            let match = searchMatches[index]
            index += 1
            guard NSIntersectionRange(match, visible).length > 0 || match.length == 0 else { continue }
            let isCurrent = currentSearchMatch.map { NSEqualRanges($0, match) } ?? false
            (isCurrent ? theme.colors.findMatchBackground : theme.colors.findMatchHighlightBackground).setFill()
            for frame in segmentFrames(for: match) where frame.intersects(rect) {
                NSBezierPath(roundedRect: frame, xRadius: 2, yRadius: 2).fill()
            }
        }
    }

    /// Character range of the laid-out viewport, or the whole document when unknown.
    private func visibleCharacterRange() -> NSRange {
        guard let textLayoutManager, let contentStorage = textContentStorage,
              let viewport = textLayoutManager.textViewportLayoutController.viewportRange else {
            return NSRange(location: 0, length: document.textStorage.length)
        }
        let start = contentStorage.documentRange.location
        let location = contentStorage.offset(from: start, to: viewport.location)
        let end = contentStorage.offset(from: start, to: viewport.endLocation)
        return NSRange(location: location, length: max(0, end - location))
    }

    private func drawCurrentLineHighlight(in rect: NSRect) {
        guard let lineFrame = lineFragmentFrame(at: selectedRange().location) else { return }
        let highlight = NSRect(x: 0, y: lineFrame.minY, width: bounds.width, height: lineFrame.height)
        guard highlight.intersects(rect) else { return }
        theme.colors.currentLineBackground.setFill()
        highlight.fill()
    }

    /// Frame (in view coordinates) of the visual line containing `location`.
    private func lineFragmentFrame(at location: Int) -> NSRect? {
        guard let textLayoutManager, let contentStorage = textContentStorage,
              let textLocation = contentStorage.location(contentStorage.documentRange.location, offsetBy: location) else { return nil }
        textLayoutManager.ensureLayout(for: NSTextRange(location: textLocation))
        guard let fragment = textLayoutManager.textLayoutFragment(for: textLocation) else { return nil }
        let offsetInFragment = contentStorage.offset(from: fragment.rangeInElement.location, to: textLocation)
        let fragmentFrame = fragment.layoutFragmentFrame
        let inset = textContainerInset
        let line = fragment.textLineFragments.first { NSLocationInRange(offsetInFragment, $0.characterRange) }
            ?? fragment.textLineFragments.last
        guard let line else {
            return NSRect(x: 0, y: fragmentFrame.minY + inset.height, width: bounds.width, height: fragmentFrame.height)
        }
        let bounds = line.typographicBounds
        return NSRect(x: 0, y: fragmentFrame.minY + bounds.minY + inset.height, width: self.bounds.width, height: bounds.height)
    }

    /// Glyph-bounding frames (in view coordinates) for a character range.
    private func segmentFrames(for range: NSRange) -> [NSRect] {
        guard let textLayoutManager, let textRange = textRange(from: range) else { return [] }
        var frames: [NSRect] = []
        let inset = textContainerInset
        textLayoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            frames.append(frame.offsetBy(dx: inset.width, dy: inset.height))
            return true
        }
        return frames
    }

    func textRange(from range: NSRange) -> NSTextRange? {
        guard let contentStorage = textContentStorage else { return nil }
        let start = contentStorage.documentRange.location
        guard let from = contentStorage.location(start, offsetBy: range.location),
              let to = contentStorage.location(start, offsetBy: range.location + range.length) else { return nil }
        return NSTextRange(location: from, end: to)
    }

    // MARK: Editing behaviour

    private var indenter: AutoIndenter {
        AutoIndenter(configuration)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let text = string as? String, text.utf8.contains(UInt8(ascii: "\r")) {
            super.insertText(LineEnding.normalizeToLF(text), replacementRange: replacementRange)
        } else {
            super.insertText(string, replacementRange: replacementRange)
        }
    }

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        let insertion = indenter.newline(at: selection.location, in: storageText)
        insertText(insertion.text, replacementRange: selection)
        setSelectedRange(NSRange(location: selection.location + insertion.caretOffset, length: 0))
    }

    override func insertTab(_ sender: Any?) {
        let selection = selectedRange()
        if spansMultipleLines(selection) {
            shiftSelectedLines(outdent: false)
            return
        }
        let column = indenter.column(of: selection.location, in: storageText)
        insertText(indenter.tabInsertion(atColumn: column), replacementRange: selection)
    }

    override func insertBacktab(_ sender: Any?) {
        shiftSelectedLines(outdent: true)
    }

    private func spansMultipleLines(_ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        let index = document.lineIndex
        return index.lineNumber(forOffset: range.location) != index.lineNumber(forOffset: range.location + range.length - 1)
    }

    /// Indents or outdents every line touched by the selection as one undoable edit.
    private func shiftSelectedLines(outdent: Bool) {
        let selection = selectedRange()
        let index = document.lineIndex
        let text = storageText
        let firstLine = index.lineNumber(forOffset: selection.location)
        let lastOffset = selection.length > 0 ? selection.location + selection.length - 1 : selection.location
        let lastLine = index.lineNumber(forOffset: lastOffset)
        let start = index.startOffset(ofLine: firstLine)
        let end = NSMaxRange(index.range(ofLine: lastLine, totalLength: text.length))
        let blockRange = NSRange(location: start, length: end - start)
        let block = text.substring(with: blockRange)
        let replacement = outdent ? indenter.outdented(block) : indenter.indented(block)
        guard replacement != block else { return }
        insertText(replacement, replacementRange: blockRange)
        if selection.length > 0 {
            setSelectedRange(NSRange(location: start, length: replacement.utf16.count))
        } else {
            let delta = replacement.utf16.count - block.utf16.count
            setSelectedRange(NSRange(location: max(start, selection.location + delta), length: 0))
        }
    }
}
