import AppKit

/// Finds spaces and tabs that sit before a line break or at the very end of the text.
enum TrailingWhitespaceTrimmer {
    /// Ranges in ascending order. Apply them back to front.
    static func ranges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        let length = text.length
        var runStart: Int? = nil
        for index in 0..<length {
            let character = text.character(at: index)
            if character == 0x20 || character == 0x09 {
                if runStart == nil { runStart = index }
            } else if character == 0x0A {
                if let start = runStart { ranges.append(NSRange(location: start, length: index - start)) }
                runStart = nil
            } else {
                runStart = nil
            }
        }
        if let start = runStart { ranges.append(NSRange(location: start, length: length - start)) }
        return ranges
    }

    /// Trims through the text view so the change is one undo step. Returns how many ranges changed.
    @MainActor
    @discardableResult
    static func trim(in textView: NSTextView) -> Int {
        guard let storage = textView.textStorage else { return 0 }
        let ranges = ranges(in: storage.mutableString)
        guard !ranges.isEmpty else { return 0 }
        let values = ranges.map { NSValue(range: $0) }
        guard textView.shouldChangeText(inRanges: values, replacementStrings: ranges.map { _ in "" }) else { return 0 }
        storage.beginEditing()
        for range in ranges.reversed() {
            storage.replaceCharacters(in: range, with: "")
        }
        storage.endEditing()
        textView.didChangeText()
        return ranges.count
    }

    /// Applies the trim to a text storage in one edit batch. Returns how many ranges changed.
    @MainActor
    @discardableResult
    static func trim(_ storage: NSTextStorage) -> Int {
        let ranges = ranges(in: storage.mutableString)
        guard !ranges.isEmpty else { return 0 }
        storage.beginEditing()
        for range in ranges.reversed() {
            storage.replaceCharacters(in: range, with: "")
        }
        storage.endEditing()
        return ranges.count
    }
}
