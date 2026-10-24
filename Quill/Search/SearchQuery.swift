import Foundation

/// What to look for. Literal searches are escaped into a regex so there is one code path.
struct SearchQuery: Equatable, Sendable {
    var text: String
    var isRegex = false
    var isCaseSensitive = false

    var isEmpty: Bool { text.isEmpty }

    func makeRegex() throws -> NSRegularExpression {
        var options: NSRegularExpression.Options = []
        if !isCaseSensitive { options.insert(.caseInsensitive) }
        if isRegex { options.insert(.anchorsMatchLines) }
        let pattern = isRegex ? text : NSRegularExpression.escapedPattern(for: text)
        return try NSRegularExpression(pattern: pattern, options: options)
    }
}
