import AppKit

/// Parses "#RGB", "#RRGGBB" and "#RRGGBBAA" the way VS Code themes write them.
enum HexColor {
    static func color(from hex: String) -> NSColor? {
        var digits = Substring(hex.trimmingCharacters(in: .whitespaces))
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        if digits.count == 3 {
            digits = Substring(digits.map { "\($0)\($0)" }.joined())
        }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let red = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
