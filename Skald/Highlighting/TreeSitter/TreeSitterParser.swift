import Foundation
import TreeSitter

/// A grammar plus its highlight query, ready to be parsed over a sub-range of the text.
struct InjectedLanguage: @unchecked Sendable {
    let language: OpaquePointer
    let query: TreeSitterQuery
}

/// Owns one `TSParser` and the latest tree for a document, plus one parser per injected
/// language (Markdown inline, fenced code blocks). Parses run on this actor, never on
/// the main thread; results are handed back as tree copies.
actor TreeSitterParser: SyntaxParser {
    private let parser: OpaquePointer
    private var tree: OpaquePointer?
    private let query: TreeSitterQuery
    private let injections: TreeSitterQuery?
    private let injectedLanguage: @Sendable (String) -> InjectedLanguage?
    private var layers: [String: Layer] = [:]

    private struct Layer {
        let parser: OpaquePointer
        var tree: OpaquePointer?
        let query: TreeSitterQuery
    }

    init?(language: OpaquePointer, query: TreeSitterQuery, injections: TreeSitterQuery? = nil,
          injectedLanguage: @escaping @Sendable (String) -> InjectedLanguage? = { _ in nil }) {
        guard let parser = ts_parser_new() else { return nil }
        guard ts_parser_set_language(parser, language) else {
            ts_parser_delete(parser)
            return nil
        }
        self.parser = parser
        self.query = query
        self.injections = injections
        self.injectedLanguage = injectedLanguage
    }

    deinit {
        if let tree { ts_tree_delete(tree) }
        ts_parser_delete(parser)
        for layer in layers.values {
            if let tree = layer.tree { ts_tree_delete(tree) }
            ts_parser_delete(layer.parser)
        }
    }

    func parse(_ text: TextSnapshot, edits: [TextEdit]?) async -> any SyntaxTree {
        guard let edits else {
            if let tree { ts_tree_delete(tree) }
            tree = nil
            for key in layers.keys {
                if let old = layers[key]?.tree { ts_tree_delete(old) }
                layers[key]?.tree = nil
            }
            return await parse(text, edits: [])
        }
        if let tree {
            Self.apply(edits, to: tree)
        }
        let input = UTF16TextInput(text)
        let parsed = input.withInput { ts_parser_parse(parser, tree, $0) }
        if let parsed {
            if let old = tree { ts_tree_delete(old) }
            tree = parsed
        }
        guard let current = tree else { return EmptySyntaxTree() }

        var result = [SyntaxLayer(tree: current, query: query)]
        result.append(contentsOf: parseInjections(root: current, text: text, input: input, edits: edits))
        return TreeSitterTree(copying: result)
    }

    // MARK: Injections

    private func parseInjections(root: OpaquePointer, text: TextSnapshot, input: UTF16TextInput, edits: [TextEdit]) -> [SyntaxLayer] {
        guard let injections else { return [] }
        let ranges = Self.injectionRanges(in: root, query: injections, text: text)

        // Drop layers whose language no longer appears.
        for key in layers.keys where ranges[key] == nil {
            if let old = layers[key]?.tree { ts_tree_delete(old) }
            if let layer = layers.removeValue(forKey: key) { ts_parser_delete(layer.parser) }
        }

        var result: [SyntaxLayer] = []
        for (languageID, tsRanges) in ranges.sorted(by: { $0.key < $1.key }) {
            guard var layer = layer(for: languageID) else { continue }
            if let old = layer.tree { Self.apply(edits, to: old) }
            let accepted = tsRanges.withUnsafeBufferPointer { buffer in
                ts_parser_set_included_ranges(layer.parser, buffer.baseAddress, UInt32(buffer.count))
            }
            guard accepted else { continue }
            if let parsed = input.withInput({ ts_parser_parse(layer.parser, layer.tree, $0) }) {
                if let old = layer.tree { ts_tree_delete(old) }
                layer.tree = parsed
            }
            layers[languageID] = layer
            if let tree = layer.tree {
                result.append(SyntaxLayer(tree: tree, query: layer.query))
            }
        }
        return result
    }

    private func layer(for languageID: String) -> Layer? {
        if let existing = layers[languageID] { return existing }
        guard let injected = injectedLanguage(languageID), let parser = ts_parser_new() else { return nil }
        guard ts_parser_set_language(parser, injected.language) else {
            ts_parser_delete(parser)
            return nil
        }
        let layer = Layer(parser: parser, tree: nil, query: injected.query)
        layers[languageID] = layer
        return layer
    }

    /// Runs the injections query: content ranges grouped by the language they hand off to.
    private static func injectionRanges(in root: OpaquePointer, query: TreeSitterQuery, text: TextSnapshot) -> [String: [TSRange]] {
        guard let contentIndex = query.captureIndex(named: "injection.content"), let cursor = ts_query_cursor_new() else { return [:] }
        defer { ts_query_cursor_delete(cursor) }
        let languageIndex = query.captureIndex(named: "injection.language")
        ts_query_cursor_exec(cursor, query.pointer, ts_tree_root_node(root))

        var result: [String: [TSRange]] = [:]
        var match = TSQueryMatch()
        while ts_query_cursor_next_match(cursor, &match) {
            guard let captures = match.captures else { continue }
            guard TreeSitterTree.predicatesHold(for: match, in: query, text: text) else { continue }
            let count = Int(match.capture_count)
            var language = query.settings[Int(match.pattern_index)]["injection.language"]
            var contentNodes: [TSNode] = []
            for position in 0..<count {
                let capture = captures[position]
                if capture.index == contentIndex {
                    contentNodes.append(capture.node)
                } else if let languageIndex, capture.index == languageIndex, language == nil {
                    let start = Int(ts_node_start_byte(capture.node)) / 2
                    let end = Int(ts_node_end_byte(capture.node)) / 2
                    language = text.substring(with: NSRange(location: start, length: max(0, end - start)))
                }
            }
            guard let language, !contentNodes.isEmpty else { continue }
            let normalized = language.lowercased().trimmingCharacters(in: .whitespaces)
            for node in contentNodes where ts_node_end_byte(node) > ts_node_start_byte(node) {
                let range = TSRange(
                    start_point: ts_node_start_point(node),
                    end_point: ts_node_end_point(node),
                    start_byte: ts_node_start_byte(node),
                    end_byte: ts_node_end_byte(node)
                )
                result[normalized, default: []].append(range)
            }
        }
        // Included ranges must be sorted and non-overlapping.
        for key in result.keys {
            var ranges = result[key]?.sorted { $0.start_byte < $1.start_byte } ?? []
            var cleaned: [TSRange] = []
            for range in ranges where cleaned.last.map({ $0.end_byte <= range.start_byte }) ?? true {
                cleaned.append(range)
            }
            ranges = cleaned
            result[key] = ranges
        }
        return result
    }

    // MARK: Helpers

    private static func apply(_ edits: [TextEdit], to tree: OpaquePointer) {
        for edit in edits {
            var inputEdit = TSInputEdit(
                start_byte: UInt32(edit.startOffset * 2),
                old_end_byte: UInt32(edit.oldEndOffset * 2),
                new_end_byte: UInt32(edit.newEndOffset * 2),
                start_point: point(edit.startPoint),
                old_end_point: point(edit.oldEndPoint),
                new_end_point: point(edit.newEndPoint)
            )
            ts_tree_edit(tree, &inputEdit)
        }
    }

    private static func point(_ point: TextPoint) -> TSPoint {
        TSPoint(row: UInt32(point.row), column: UInt32(point.column * 2))
    }
}

/// Returned when parsing produced nothing (should not happen without cancellation).
struct EmptySyntaxTree: SyntaxTree {
    func highlights(in range: NSRange, text: TextSnapshot) -> [HighlightSpan] { [] }
}
