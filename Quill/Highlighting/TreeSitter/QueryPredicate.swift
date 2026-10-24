import Foundation

/// The subset of query predicates the C runtime leaves to the host: text comparisons.
/// Unknown predicates and `#set!`-style directives are treated as always true.
enum QueryPredicate {
    case equalsString(capture: UInt32, value: String, negated: Bool)
    case equalsCapture(first: UInt32, second: UInt32, negated: Bool)
    case matches(capture: UInt32, regex: NSRegularExpression, negated: Bool)
    case anyOf(capture: UInt32, values: Set<String>, negated: Bool)

    /// `text(captureIndex)` returns the text of that capture in the current match, or nil.
    func evaluate(text: (UInt32) -> String?) -> Bool {
        switch self {
        case .equalsString(let capture, let value, let negated):
            return (text(capture) == value) != negated
        case .equalsCapture(let first, let second, let negated):
            return (text(first) == text(second)) != negated
        case .matches(let capture, let regex, let negated):
            guard let candidate = text(capture) else { return negated }
            let found = regex.firstMatch(in: candidate, range: NSRange(location: 0, length: candidate.utf16.count)) != nil
            return found != negated
        case .anyOf(let capture, let values, let negated):
            guard let candidate = text(capture) else { return negated }
            return values.contains(candidate) != negated
        }
    }

    /// Builds a predicate from its parsed steps: the operator name followed by capture
    /// indices and string literals. Returns nil for operators that need no evaluation.
    static func make(operator name: String, arguments: [Argument]) -> QueryPredicate? {
        switch name {
        case "eq?", "not-eq?", "any-eq?", "any-not-eq?":
            let negated = name.contains("not-")
            guard arguments.count == 2, case .capture(let first) = arguments[0] else { return nil }
            switch arguments[1] {
            case .capture(let second): return .equalsCapture(first: first, second: second, negated: negated)
            case .string(let value): return .equalsString(capture: first, value: value, negated: negated)
            }
        case "match?", "not-match?", "any-match?", "any-not-match?", "lua-match?", "not-lua-match?":
            let negated = name.contains("not-")
            guard arguments.count == 2, case .capture(let capture) = arguments[0], case .string(let pattern) = arguments[1] else { return nil }
            let source = name.contains("lua-") ? Self.regexFromLuaPattern(pattern) : pattern
            guard let regex = try? NSRegularExpression(pattern: source) else { return nil }
            return .matches(capture: capture, regex: regex, negated: negated)
        case "any-of?", "not-any-of?":
            let negated = name.hasPrefix("not-")
            guard arguments.count >= 2, case .capture(let capture) = arguments[0] else { return nil }
            let values = arguments.dropFirst().compactMap { argument -> String? in
                if case .string(let value) = argument { return value }
                return nil
            }
            return .anyOf(capture: capture, values: Set(values), negated: negated)
        default:
            return nil
        }
    }

    enum Argument {
        case capture(UInt32)
        case string(String)
    }

    /// Good-enough translation of Lua patterns (`%a`, `%d`, `%w`, `%s`) to ICU regex.
    static func regexFromLuaPattern(_ pattern: String) -> String {
        var result = ""
        var iterator = pattern.makeIterator()
        while let character = iterator.next() {
            if character == "%", let next = iterator.next() {
                switch next {
                case "a": result += "[A-Za-z]"
                case "d": result += "[0-9]"
                case "w": result += "[A-Za-z0-9]"
                case "s": result += "\\s"
                case "u": result += "[A-Z]"
                case "l": result += "[a-z]"
                case "p": result += "\\p{P}"
                default: result += "\\" + String(next)
                }
            } else if character == "-" {
                result += "*?"
            } else {
                result.append(character)
            }
        }
        return result
    }
}
