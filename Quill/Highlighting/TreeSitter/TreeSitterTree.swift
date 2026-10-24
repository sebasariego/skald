import Foundation
import TreeSitter

/// One parsed grammar over (part of) the document: the tree and its highlight query.
struct SyntaxLayer {
    let tree: OpaquePointer
    let query: TreeSitterQuery
}

/// A parse result the main actor can query. Owns copies of the trees, so the parser
/// actor is free to keep editing its own. The first layer is the document's language;
/// further layers are injected grammars (Markdown inline, fenced code) over sub-ranges.
final class TreeSitterTree: SyntaxTree, @unchecked Sendable {
    private let layers: [SyntaxLayer]

    init(copying layers: [SyntaxLayer]) {
        self.layers = layers.map { SyntaxLayer(tree: ts_tree_copy($0.tree), query: $0.query) }
    }

    deinit {
        for layer in layers { ts_tree_delete(layer.tree) }
    }

    func highlights(in range: NSRange, text: TextSnapshot) -> [HighlightSpan] {
        guard range.length > 0 else { return [] }
        var spans: [HighlightSpan] = []
        for layer in layers {
            spans.append(contentsOf: Self.highlights(in: range, layer: layer, text: text))
        }
        if layers.count > 1 {
            // Document order, outer spans before the inner ones that refine them.
            spans.sort { lhs, rhs in
                if lhs.range.location != rhs.range.location { return lhs.range.location < rhs.range.location }
                return lhs.range.length > rhs.range.length
            }
        }
        return spans
    }

    private static func highlights(in range: NSRange, layer: SyntaxLayer, text: TextSnapshot) -> [HighlightSpan] {
        let tree = layer.tree
        let query = layer.query
        guard let cursor = ts_query_cursor_new() else { return [] }
        defer { ts_query_cursor_delete(cursor) }
        ts_query_cursor_set_byte_range(cursor, UInt32(range.location * 2), UInt32(NSMaxRange(range) * 2))
        ts_query_cursor_exec(cursor, query.pointer, ts_tree_root_node(tree))

        var spans: [HighlightSpan] = []
        var match = TSQueryMatch()
        var captureIndex: UInt32 = 0
        var matchVerdicts: [UInt32: Bool] = [:]
        var lastNode: UnsafeRawPointer?
        var lastNodeSpanIndex = 0
        var lastPattern: UInt16 = 0

        while ts_query_cursor_next_capture(cursor, &match, &captureIndex) {
            guard let captures = match.captures else { continue }
            let capture = captures[Int(captureIndex)]
            guard Int(capture.index) < query.captureNames.count else { continue }
            let name = query.captureNames[Int(capture.index)]
            // Spell-check hints are metadata, not highlighting.
            if name == "spell" || name == "nospell" { continue }

            // Evaluate this match's predicates once, the first time any of its captures shows up.
            let verdict: Bool
            if let known = matchVerdicts[match.id] {
                verdict = known
            } else {
                verdict = Self.predicatesHold(for: match, in: query, text: text)
                matchVerdicts[match.id] = verdict
            }
            guard verdict else { continue }

            let start = Int(ts_node_start_byte(capture.node)) / 2
            let end = Int(ts_node_end_byte(capture.node)) / 2
            guard end > start else { continue }
            let span = HighlightSpan(range: NSRange(location: start, length: end - start), capture: name)

            // Captures for one node arrive together, ordered by pattern. The query files
            // put specific patterns after general ones, so the later pattern wins.
            let nodeID = UnsafeRawPointer(capture.node.id)
            if nodeID == lastNode, lastNodeSpanIndex < spans.count {
                if match.pattern_index != lastPattern {
                    spans.removeSubrange(lastNodeSpanIndex...)
                    spans.append(span)
                    lastPattern = match.pattern_index
                } else {
                    spans.append(span)
                }
                continue
            }
            lastNode = nodeID
            lastPattern = match.pattern_index
            lastNodeSpanIndex = spans.count
            spans.append(span)
        }
        return spans
    }

    static func predicatesHold(for match: TSQueryMatch, in query: TreeSitterQuery, text: TextSnapshot) -> Bool {
        let pattern = Int(match.pattern_index)
        guard pattern < query.predicates.count, !query.predicates[pattern].isEmpty, let captures = match.captures else { return true }
        let count = Int(match.capture_count)
        func captureText(_ index: UInt32) -> String? {
            for position in 0..<count where captures[position].index == index {
                let node = captures[position].node
                let start = Int(ts_node_start_byte(node)) / 2
                let end = Int(ts_node_end_byte(node)) / 2
                return text.substring(with: NSRange(location: start, length: max(0, end - start)))
            }
            return nil
        }
        return query.predicates[pattern].allSatisfy { $0.evaluate(text: captureText) }
    }
}
