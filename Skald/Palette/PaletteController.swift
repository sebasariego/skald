import Foundation
import Observation

/// The overlay used by the command palette and quick open: one query, a ranked list,
/// and a keyboard-driven selection. Matching runs off the main actor for large lists.
@MainActor
@Observable
final class PaletteController {
    private(set) var isPresented = false
    private(set) var placeholder = ""
    var query = "" {
        didSet { if query != oldValue { scheduleFilter() } }
    }
    private(set) var results: [PaletteResult] = []
    var selectedIndex = 0
    /// Bumped when the keyboard moves the selection; the list scrolls only for these,
    /// never for hover, which would fight the user's own scrolling.
    private(set) var keyboardSelectionVersion = 0

    nonisolated static let maximumResults = 60

    @ObservationIgnored private var candidates: [PaletteCandidate] = []
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    func present(placeholder: String, candidates: [PaletteCandidate]) {
        self.placeholder = placeholder
        self.candidates = candidates
        query = ""
        selectedIndex = 0
        isPresented = true
        scheduleFilter(immediately: true)
    }

    /// Replaces the candidate list while open (e.g. the file index finished).
    func updateCandidates(_ candidates: [PaletteCandidate]) {
        guard isPresented else { return }
        self.candidates = candidates
        scheduleFilter(immediately: true)
    }

    func dismiss() {
        filterTask?.cancel()
        isPresented = false
        candidates = []
        results = []
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
        keyboardSelectionVersion += 1
    }

    func activateSelection() {
        guard results.indices.contains(selectedIndex) else { return }
        let candidate = results[selectedIndex].candidate
        guard candidate.isEnabled else { return }
        dismiss()
        candidate.perform()
    }

    func activate(_ result: PaletteResult) {
        guard result.candidate.isEnabled else { return }
        dismiss()
        result.candidate.perform()
    }

    /// Waits for the in-flight filter. Tests use this.
    func waitForFilter() async {
        await filterTask?.value
    }

    private func scheduleFilter(immediately: Bool = false) {
        filterTask?.cancel()
        generation += 1
        let generation = generation
        let query = query
        let candidates = candidates
        filterTask = Task { [weak self] in
            if !immediately, candidates.count > 500 {
                try? await Task.sleep(for: .milliseconds(30))
            }
            guard !Task.isCancelled else { return }
            let ranked = await Self.rank(query: query, buffers: candidates.map { ($0.searchBuffer, $0.originalBuffer) })
            guard !Task.isCancelled, let self, generation == self.generation else { return }
            self.results = ranked.map { PaletteResult(candidate: candidates[$0.index], positions: $0.positions) }
            self.selectedIndex = 0
        }
    }

    private struct Ranked: Sendable {
        let index: Int
        let score: Int
        let positions: [Int]
    }

    nonisolated private static func rank(query: String, buffers: [([UInt16], [UInt16])]) async -> [Ranked] {
        let pattern = FuzzyMatcher.lowercasedUTF16(query)
        if pattern.isEmpty {
            return buffers.prefix(maximumResults).enumerated().map { Ranked(index: $0.offset, score: 0, positions: []) }
        }
        var ranked: [Ranked] = []
        for (index, pair) in buffers.enumerated() {
            if let match = FuzzyMatcher.match(pattern, in: pair.0, original: pair.1) {
                ranked.append(Ranked(index: index, score: match.score, positions: match.positions))
            }
        }
        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if buffers[lhs.index].0.count != buffers[rhs.index].0.count { return buffers[lhs.index].0.count < buffers[rhs.index].0.count }
            return lhs.index < rhs.index
        }
        return Array(ranked.prefix(maximumResults))
    }
}
