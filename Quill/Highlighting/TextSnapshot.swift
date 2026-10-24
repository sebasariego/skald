import Foundation

/// An immutable copy of a document's text that background parsers can read freely.
/// `NSString` gives O(1) UTF-16 access, which is what parsers and queries index by.
struct TextSnapshot: @unchecked Sendable {
    let string: NSString

    init(_ string: NSString) {
        // `copy()` on a mutable string yields an immutable one; on an immutable string it is free.
        self.string = (string.copy() as? NSString) ?? NSString(string: string as String)
    }

    init(_ text: String) {
        string = text as NSString
    }

    var length: Int { string.length }

    func substring(with range: NSRange) -> String {
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: length))
        return string.substring(with: clamped)
    }
}
