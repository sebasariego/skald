import AppKit

/// Resolves a tree-sitter capture name ("keyword.control.return") to a theme style by
/// translating it to TextMate scopes and picking the theme rule with the longest match.
/// Results are memoized because the same few dozen captures repeat endlessly.
final class CaptureScopeMap {
    private let theme: Theme
    private var cache: [String: TokenStyle?] = [:]

    init(theme: Theme) {
        self.theme = theme
    }

    /// TextMate scopes each capture (or capture prefix) corresponds to, best first.
    static let scopeCandidates: [String: [String]] = [
        "comment": ["comment"],
        "comment.documentation": ["comment.block.documentation", "comment"],
        "keyword": ["keyword", "storage.type"],
        "keyword.function": ["storage.type.function", "keyword.declaration", "keyword"],
        "keyword.operator": ["keyword.operator"],
        "keyword.return": ["keyword.control.return", "keyword.control", "keyword"],
        "keyword.import": ["keyword.control.import", "keyword.other.import", "keyword.control", "keyword"],
        "keyword.control": ["keyword.control", "keyword"],
        "keyword.modifier": ["storage.modifier", "keyword"],
        "keyword.type": ["storage.type", "keyword"],
        "include": ["keyword.control.import", "keyword.control", "keyword"],
        "conditional": ["keyword.control.conditional", "keyword.control", "keyword"],
        "repeat": ["keyword.control.loop", "keyword.control", "keyword"],
        "exception": ["keyword.control.exception", "keyword.control", "keyword"],
        "storageclass": ["storage.modifier", "storage.type"],
        "operator": ["keyword.operator"],
        "string": ["string"],
        "string.escape": ["constant.character.escape", "string"],
        "string.special": ["string.regexp", "string"],
        "string.regex": ["string.regexp", "string"],
        "escape": ["constant.character.escape"],
        "character": ["constant.character", "string"],
        "number": ["constant.numeric"],
        "float": ["constant.numeric"],
        "boolean": ["constant.language.boolean", "constant.language"],
        "constant": ["constant", "variable.other.constant"],
        "constant.builtin": ["constant.language", "support.constant"],
        "constant.macro": ["entity.name.function.preprocessor", "constant"],
        "function": ["entity.name.function", "support.function"],
        "function.call": ["entity.name.function", "support.function"],
        "function.method": ["entity.name.function.member", "entity.name.function"],
        "function.method.call": ["entity.name.function.member", "entity.name.function"],
        "function.builtin": ["support.function", "entity.name.function"],
        "function.macro": ["entity.name.function.macro", "entity.name.function"],
        "method": ["entity.name.function.member", "entity.name.function"],
        "constructor": ["entity.name.function.constructor", "entity.name.type"],
        "type": ["entity.name.type", "support.type", "storage.type"],
        "type.builtin": ["support.type", "storage.type", "entity.name.type"],
        "type.definition": ["entity.name.type", "storage.type"],
        "type.qualifier": ["storage.modifier"],
        "namespace": ["entity.name.namespace", "entity.name.type.module"],
        "module": ["entity.name.namespace", "entity.name.type.module"],
        "variable": ["variable"],
        "variable.builtin": ["variable.language"],
        "variable.parameter": ["variable.parameter"],
        "variable.member": ["variable.other.property", "variable.other.member"],
        "variable.other.member": ["variable.other.property", "variable.other.member"],
        "parameter": ["variable.parameter"],
        "property": ["variable.other.property", "support.variable.property", "variable.other.member"],
        "field": ["variable.other.property", "variable.other.member"],
        "attribute": ["entity.other.attribute-name", "meta.attribute", "storage.modifier"],
        "label": ["entity.name.label"],
        "tag": ["entity.name.tag"],
        "punctuation": ["punctuation"],
        "punctuation.bracket": ["punctuation.section", "meta.brace", "punctuation"],
        "punctuation.delimiter": ["punctuation.separator", "punctuation"],
        "punctuation.special": ["punctuation.definition", "keyword.operator", "punctuation"],
        "symbol": ["constant.other.symbol"],
        "text.title": ["markup.heading", "entity.name.section"],
        "markup.heading": ["markup.heading", "entity.name.section"],
        "text.strong": ["markup.bold"],
        "markup.strong": ["markup.bold"],
        "markup.bold": ["markup.bold"],
        "text.emphasis": ["markup.italic"],
        "markup.italic": ["markup.italic"],
        "text.literal": ["markup.inline.raw", "markup.raw"],
        "markup.raw": ["markup.inline.raw", "markup.raw"],
        "text.uri": ["markup.underline.link", "string.other.link"],
        "markup.link.url": ["markup.underline.link", "string.other.link"],
        "markup.link": ["markup.underline.link", "string.other.link"],
        "text.reference": ["markup.underline.link", "string.other.link"],
        "markup.list": ["punctuation.definition.list", "markup.list"],
        "markup.quote": ["markup.quote"],
        "none": [],
        "spell": [],
        "nospell": [],
    ]

    func style(for capture: String) -> TokenStyle? {
        if let cached = cache[capture] { return cached }
        let resolved = resolve(capture)
        cache[capture] = resolved
        return resolved
    }

    private func resolve(_ capture: String) -> TokenStyle? {
        for prefix in Self.prefixes(of: capture) {
            var candidates = Self.scopeCandidates[prefix] ?? []
            // The capture itself is often a valid TextMate scope ("comment", "string").
            if candidates.isEmpty { candidates = [prefix] }
            for scope in candidates {
                if let style = bestRule(matching: scope) { return style }
            }
        }
        return nil
    }

    /// "a.b.c" -> ["a.b.c", "a.b", "a"]
    static func prefixes(of capture: String) -> [String] {
        var parts = capture.split(separator: ".").map(String.init)
        var result: [String] = []
        while !parts.isEmpty {
            result.append(parts.joined(separator: "."))
            parts.removeLast()
        }
        return result
    }

    /// The rule whose scope selector is the longest dotted prefix of `scope`. Later rules win ties.
    private func bestRule(matching scope: String) -> TokenStyle? {
        var best: (length: Int, style: TokenStyle)? = nil
        for rule in theme.tokenRules {
            for selector in rule.scopes {
                guard Self.selector(selector, matches: scope) else { continue }
                if best == nil || selector.count >= best!.length {
                    best = (selector.count, rule.style)
                }
            }
        }
        return best?.style
    }

    /// TextMate prefix match on dot boundaries. Descendant selectors ("source.swift keyword")
    /// use their last component, since every document here is a single language.
    static func selector(_ selector: String, matches scope: String) -> Bool {
        let effective = selector.split(separator: " ").last.map(String.init) ?? selector
        guard !effective.isEmpty else { return false }
        if scope == effective { return true }
        return scope.hasPrefix(effective + ".")
    }
}
