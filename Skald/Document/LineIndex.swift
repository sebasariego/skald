import Foundation

/// UTF-16 offsets of every line start, kept in sync with edits so the gutter and
/// go-to-line never have to rescan a large file. Only "\n" ends a line; documents
/// are LF-normalized on load and on paste.
struct LineIndex: Equatable, Sendable {
    /// `lineStarts[i]` is the offset of the first character of line `i`. Always begins with 0.
    private(set) var lineStarts: [Int] = [0]

    init() {}

    init(text: NSString) {
        lineStarts = Self.lineStarts(in: text, offsetBy: 0, includingZero: true)
    }

    var lineCount: Int { lineStarts.count }

    /// Zero-based line containing `offset`. Offsets past the end map to the last line.
    func lineNumber(forOffset offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// (row, column) of an offset; columns count UTF-16 units from the line start.
    func point(forOffset offset: Int) -> TextPoint {
        let line = lineNumber(forOffset: offset)
        return TextPoint(row: line, column: max(0, offset - lineStarts[line]))
    }

    /// Offset of the first character of a zero-based line.
    func startOffset(ofLine line: Int) -> Int {
        lineStarts[max(0, min(line, lineStarts.count - 1))]
    }

    /// Range of a zero-based line excluding its "\n", given the total text length.
    func range(ofLine line: Int, totalLength: Int) -> NSRange {
        let start = startOffset(ofLine: line)
        let end: Int
        if line + 1 < lineStarts.count {
            end = lineStarts[line + 1] - 1
        } else {
            end = totalLength
        }
        return NSRange(location: start, length: max(0, end - start))
    }

    /// Applies an edit that replaced `oldRange` with `newText`.
    mutating func replaceCharacters(in oldRange: NSRange, with newText: NSString) {
        let oldEnd = oldRange.location + oldRange.length
        let delta = newText.length - oldRange.length

        // Lines whose start lies in (location, oldEnd] began with a "\n" inside the removed text.
        let firstRemoved = firstIndex(withStartGreaterThan: oldRange.location)
        let firstKept = firstIndex(withStartGreaterThan: oldEnd)

        let inserted = Self.lineStarts(in: newText, offsetBy: oldRange.location, includingZero: false)
        if delta != 0 {
            for index in firstKept..<lineStarts.count {
                lineStarts[index] += delta
            }
        }
        lineStarts.replaceSubrange(firstRemoved..<firstKept, with: inserted)
    }

    private func firstIndex(withStartGreaterThan offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] > offset { high = mid } else { low = mid + 1 }
        }
        return low
    }

    private static func lineStarts(in text: NSString, offsetBy base: Int, includingZero: Bool) -> [Int] {
        var starts: [Int] = includingZero ? [0] : []
        let length = text.length
        guard length > 0 else { return starts }
        var buffer = [unichar](repeating: 0, count: min(length, 1 << 16))
        var position = 0
        while position < length {
            let chunk = NSRange(location: position, length: min(buffer.count, length - position))
            text.getCharacters(&buffer, range: chunk)
            buffer.withUnsafeBufferPointer { pointer in
                var index = 0
                while index < chunk.length {
                    if pointer[index] == 0x0A {
                        starts.append(base + position + index + 1)
                    }
                    index += 1
                }
            }
            position += chunk.length
        }
        return starts
    }
}
