import Foundation
import TreeSitter

struct TreeSitterQueryError: LocalizedError {
    let kind: String
    let offset: Int
    let context: String

    var errorDescription: String? {
        "Highlight query error (\(kind)) at offset \(offset): \(context)"
    }
}

/// A compiled highlight query: capture names plus the host-evaluated predicates of
/// each pattern. Immutable after construction, so it is shared freely across threads.
final class TreeSitterQuery: @unchecked Sendable {
    let pointer: OpaquePointer
    let captureNames: [String]
    /// Predicates per pattern index.
    let predicates: [[QueryPredicate]]
    /// `#set!` directives per pattern index, e.g. `injection.language` -> `markdown_inline`.
    let settings: [[String: String]]

    init(language: OpaquePointer, source: String) throws {
        var errorOffset: UInt32 = 0
        var errorType = TSQueryErrorNone
        let utf8 = Array(source.utf8)
        let compiled = utf8.withUnsafeBufferPointer { bytes -> OpaquePointer? in
            bytes.baseAddress.flatMap { base in
                base.withMemoryRebound(to: CChar.self, capacity: bytes.count) { chars in
                    ts_query_new(language, chars, UInt32(bytes.count), &errorOffset, &errorType)
                }
            }
        }
        guard let compiled else {
            let offset = Int(errorOffset)
            let start = source.utf8.index(source.utf8.startIndex, offsetBy: min(offset, utf8.count))
            let end = source.utf8.index(start, offsetBy: 40, limitedBy: source.utf8.endIndex) ?? source.utf8.endIndex
            throw TreeSitterQueryError(kind: Self.describe(errorType), offset: offset, context: String(source[start..<end]))
        }
        pointer = compiled

        let captureCount = ts_query_capture_count(compiled)
        captureNames = (0..<captureCount).map { index in
            var length: UInt32 = 0
            guard let name = ts_query_capture_name_for_id(compiled, index, &length) else { return "" }
            return String(decoding: UnsafeRawBufferPointer(start: name, count: Int(length)), as: UTF8.self)
        }

        let patternCount = ts_query_pattern_count(compiled)
        let parsed = (0..<patternCount).map { pattern in
            Self.parseSteps(forPattern: pattern, in: compiled)
        }
        predicates = parsed.map(\.predicates)
        settings = parsed.map(\.settings)
    }

    func captureIndex(named name: String) -> UInt32? {
        captureNames.firstIndex(of: name).map(UInt32.init)
    }

    deinit {
        ts_query_delete(pointer)
    }

    private static func parseSteps(forPattern pattern: UInt32, in query: OpaquePointer) -> (predicates: [QueryPredicate], settings: [String: String]) {
        var stepCount: UInt32 = 0
        guard let steps = ts_query_predicates_for_pattern(query, pattern, &stepCount), stepCount > 0 else { return ([], [:]) }
        var result: [QueryPredicate] = []
        var settings: [String: String] = [:]
        var operatorName: String?
        var arguments: [QueryPredicate.Argument] = []
        for index in 0..<Int(stepCount) {
            let step = steps[index]
            switch step.type {
            case TSQueryPredicateStepTypeString:
                var length: UInt32 = 0
                let value = ts_query_string_value_for_id(query, step.value_id, &length).map {
                    String(decoding: UnsafeRawBufferPointer(start: $0, count: Int(length)), as: UTF8.self)
                } ?? ""
                if operatorName == nil { operatorName = value } else { arguments.append(.string(value)) }
            case TSQueryPredicateStepTypeCapture:
                arguments.append(.capture(step.value_id))
            default: // TSQueryPredicateStepTypeDone
                if operatorName == "set!", arguments.count == 2,
                   case .string(let key) = arguments[0], case .string(let value) = arguments[1] {
                    settings[key] = value
                } else if let operatorName, let predicate = QueryPredicate.make(operator: operatorName, arguments: arguments) {
                    result.append(predicate)
                }
                operatorName = nil
                arguments = []
            }
        }
        return (result, settings)
    }

    private static func describe(_ error: TSQueryError) -> String {
        switch error {
        case TSQueryErrorSyntax: return "syntax"
        case TSQueryErrorNodeType: return "unknown node type"
        case TSQueryErrorField: return "unknown field"
        case TSQueryErrorCapture: return "unknown capture"
        case TSQueryErrorStructure: return "structure"
        case TSQueryErrorLanguage: return "language"
        default: return "unknown"
        }
    }
}
