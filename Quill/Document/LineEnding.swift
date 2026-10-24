import Foundation

/// The newline convention of a file on disk. In memory every document uses LF.
enum LineEnding: String, CaseIterable, Codable, Sendable {
    case lf
    case crlf
    case cr

    var string: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        }
    }

    var displayName: String {
        switch self {
        case .lf: return "LF"
        case .crlf: return "CRLF"
        case .cr: return "CR"
        }
    }

    /// Detects the convention from the first line break. Defaults to LF when there is none.
    static func detect(in text: String) -> LineEnding {
        var sawCR = false
        for byte in text.utf8 {
            if sawCR {
                return byte == UInt8(ascii: "\n") ? .crlf : .cr
            }
            if byte == UInt8(ascii: "\n") { return .lf }
            if byte == UInt8(ascii: "\r") { sawCR = true }
        }
        return sawCR ? .cr : .lf
    }

    /// Rewrites every CRLF and CR line break as LF.
    static func normalizeToLF(_ text: String) -> String {
        guard text.utf8.contains(UInt8(ascii: "\r")) else { return text }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Rewrites LF line breaks in `text` (assumed normalized) to this convention.
    func apply(to text: String) -> String {
        switch self {
        case .lf: return text
        case .crlf, .cr: return text.replacingOccurrences(of: "\n", with: string)
        }
    }
}
