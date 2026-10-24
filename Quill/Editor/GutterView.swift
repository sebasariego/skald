import AppKit

/// Line numbers. Reads layout only through `NSTextLayoutManager` so the text view
/// stays on TextKit 2.
final class GutterView: NSRulerView {
    private weak var textView: CodeTextView?
    private var font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private var colors = ThemeLoader.fallbackTheme.colors
    private var backgroundOpacity = 1.0
    private var lastDigitCount = 0

    init(scrollView: NSScrollView, textView: CodeTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        updateThickness(force: true)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("GutterView is created in code")
    }

    /// Rulers are flipped like text views; make it explicit so numbers run top to bottom.
    override var isFlipped: Bool { true }

    func apply(_ configuration: EditorConfiguration, theme: Theme) {
        font = NSFont.monospacedDigitSystemFont(ofSize: configuration.fontSize, weight: .regular)
        colors = theme.colors
        backgroundOpacity = configuration.clampedBackgroundOpacity
        updateThickness(force: true)
        needsDisplay = true
    }

    /// Widens the gutter when the line count gains a digit.
    func updateThickness(force: Bool = false) {
        guard let textView else { return }
        let digits = max(3, String(textView.document.lineIndex.lineCount).count)
        guard force || digits != lastDigitCount else { return }
        lastDigitCount = digits
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        ruleThickness = ceil(digitWidth * CGFloat(digits)) + 20
    }

    /// Replaces `NSRulerView`'s drawing, which adds a hairline along the text edge and
    /// arrives with a context that is not clipped to the ruler's column.
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        colors.editorBackground.withAlphaComponent(backgroundOpacity).setFill()
        bounds.intersection(dirtyRect).fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let textLayoutManager = textView.textLayoutManager,
              let contentStorage = textView.textContentStorage else { return }

        let lineIndex = textView.document.lineIndex
        let currentLine = lineIndex.lineNumber(forOffset: textView.selectedRange().location)
        let visibleRect = textView.visibleRect
        let inset = textView.textContainerInset
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colors.lineNumber]
        let currentAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colors.lineNumberActive]
        let documentStart = contentStorage.documentRange.location

        // Find the fragment under the top of the viewport and walk down from there. Never
        // fall back to the document start on a long file: that would lay out everything.
        let topPoint = CGPoint(x: 0, y: max(0, visibleRect.minY - inset.height))
        let startLocation = textLayoutManager.textLayoutFragment(for: topPoint)?.rangeInElement.location
            ?? textLayoutManager.textViewportLayoutController.viewportRange?.location
            ?? documentStart

        textLayoutManager.enumerateTextLayoutFragments(from: startLocation, options: [.ensuresLayout, .ensuresExtraLineFragment]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let yInTextView = frame.minY + inset.height
            if yInTextView > visibleRect.maxY { return false }

            let offset = contentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)
            let line = lineIndex.lineNumber(forOffset: offset)
            let label = String(line + 1) as NSString
            let isCurrent = line == currentLine
            let labelAttributes = isCurrent ? currentAttributes : attributes
            let size = label.size(withAttributes: labelAttributes)

            // Align the number's baseline with the first line fragment of the paragraph.
            let firstLineHeight = fragment.textLineFragments.first?.typographicBounds.height ?? frame.height
            let yInGutter = self.convert(NSPoint(x: 0, y: yInTextView), from: textView).y
            let drawY = yInGutter + (firstLineHeight - size.height) / 2
            let drawX = self.ruleThickness - size.width - 10
            label.draw(at: NSPoint(x: drawX, y: drawY), withAttributes: labelAttributes)
            return true
        }
    }
}
