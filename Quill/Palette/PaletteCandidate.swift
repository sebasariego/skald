import Foundation

/// A row the palette can show and run. Title and subtitle are display text; the
/// search buffer is what fuzzy matching sees (lowercased UTF-16 of the title).
struct PaletteCandidate: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let detail: String?
    let isEnabled: Bool
    let searchBuffer: [UInt16]
    let originalBuffer: [UInt16]
    let perform: @MainActor () -> Void

    init(id: String, title: String, subtitle: String? = nil, detail: String? = nil, isEnabled: Bool = true, searchBuffer: [UInt16]? = nil, originalBuffer: [UInt16]? = nil, perform: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.isEnabled = isEnabled
        self.searchBuffer = searchBuffer ?? FuzzyMatcher.lowercasedUTF16(title)
        self.originalBuffer = originalBuffer ?? Array(title.utf16)
        self.perform = perform
    }
}

/// A candidate plus where the query matched, ready to draw.
struct PaletteResult: Identifiable {
    let candidate: PaletteCandidate
    let positions: [Int]

    var id: String { candidate.id }
}
