import AppKit
import Observation

/// State and actions for the find bar. Searches run on a text snapshot off the main
/// actor; results are applied back here and pushed to the active editor for drawing.
@MainActor
@Observable
final class FindController {
    var isVisible = false
    var showsReplace = false
    var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    var replacement = ""
    var isRegex = false { didSet { if isRegex != oldValue { scheduleSearch() } } }
    var isCaseSensitive = false { didSet { if isCaseSensitive != oldValue { scheduleSearch() } } }

    private(set) var matches: [NSRange] = []
    private(set) var currentIndex: Int?
    private(set) var errorMessage: String?
    /// Incremented whenever the query field should take focus.
    private(set) var focusRequest = 0

    @ObservationIgnored private weak var textView: CodeTextView? {
        didSet { observeStorage() }
    }
    @ObservationIgnored private var storageObserver: NSObjectProtocol?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    var searchQuery: SearchQuery {
        SearchQuery(text: query, isRegex: isRegex, isCaseSensitive: isCaseSensitive)
    }

    var statusText: String {
        if let errorMessage { return errorMessage }
        if query.isEmpty { return "" }
        if matches.isEmpty { return "No results" }
        if let currentIndex { return "\(currentIndex + 1) of \(matches.count)" }
        return "\(matches.count) results"
    }

    // MARK: Lifecycle

    func attach(_ view: CodeTextView?) {
        guard view !== textView else { return }
        textView?.searchMatches = []
        textView?.currentSearchMatch = nil
        textView = view
        if isVisible { scheduleSearch(immediately: true) }
    }

    func show(withReplace: Bool) {
        if let selection = selectedTextForSearch() { query = selection }
        showsReplace = withReplace || (isVisible && showsReplace)
        isVisible = true
        focusRequest += 1
        scheduleSearch(immediately: true)
    }

    func hide() {
        isVisible = false
        clearMatches()
        textView?.window?.makeFirstResponder(textView)
    }

    func useSelectionForFind() {
        if let selection = selectedTextForSearch() { query = selection }
    }

    // MARK: Navigation

    func findNext() {
        guard !matches.isEmpty else { return }
        let next: Int
        if let currentIndex {
            next = (currentIndex + 1) % matches.count
        } else {
            next = TextSearcher.indexOfMatch(atOrAfter: NSMaxRange(textView?.selectedRange() ?? NSRange()), in: matches) ?? 0
        }
        select(index: next)
    }

    func findPrevious() {
        guard !matches.isEmpty else { return }
        let previous: Int
        if let currentIndex {
            previous = (currentIndex - 1 + matches.count) % matches.count
        } else {
            let after = TextSearcher.indexOfMatch(atOrAfter: textView?.selectedRange().location ?? 0, in: matches) ?? 0
            previous = (after - 1 + matches.count) % matches.count
        }
        select(index: previous)
    }

    // MARK: Replacing

    func replaceCurrent() {
        guard let textView, let currentIndex, matches.indices.contains(currentIndex) else {
            findNext()
            return
        }
        let match = matches[currentIndex]
        let text = TextSearcher.replacement(for: match, query: searchQuery, template: replacement, in: textView.document.snapshot())
        textView.insertText(text, replacementRange: match)
        let resumeAt = match.location + text.utf16.count
        searchNow(selectingMatchAtOrAfter: resumeAt)
    }

    func replaceAll() {
        guard let textView, !matches.isEmpty else { return }
        let snapshot = textView.document.snapshot()
        let query = searchQuery
        let replacements = matches.map { TextSearcher.replacement(for: $0, query: query, template: replacement, in: snapshot) }
        let ranges = matches.map { NSValue(range: $0) }
        guard textView.shouldChangeText(inRanges: ranges, replacementStrings: replacements) else { return }
        let storage = textView.document.textStorage
        storage.beginEditing()
        for (range, text) in zip(matches, replacements).reversed() {
            storage.replaceCharacters(in: range, with: text)
        }
        storage.endEditing()
        textView.didChangeText()
        searchNow(selectingMatchAtOrAfter: nil)
    }

    // MARK: Searching

    private func scheduleSearch(immediately: Bool = false) {
        searchTask?.cancel()
        generation += 1
        let generation = generation
        searchTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(80)) }
            guard !Task.isCancelled, let self else { return }
            await self.runSearch(generation: generation, selectingMatchAtOrAfter: nil)
        }
    }

    private func searchNow(selectingMatchAtOrAfter location: Int?) {
        searchTask?.cancel()
        generation += 1
        let generation = generation
        searchTask = Task { [weak self] in
            await self?.runSearch(generation: generation, selectingMatchAtOrAfter: location)
        }
    }

    private func runSearch(generation: Int, selectingMatchAtOrAfter location: Int?) async {
        guard isVisible, let textView else {
            clearMatches()
            return
        }
        let snapshot = textView.document.snapshot()
        let query = searchQuery
        var found: [NSRange] = []
        var searchError: String?
        do {
            found = try await TextSearcher.matches(for: query, in: snapshot)
        } catch {
            found = []
            if !query.isEmpty { searchError = TextSearchError.invalidPattern.localizedDescription }
        }
        guard generation == self.generation else { return }
        matches = found
        errorMessage = searchError
        if let location {
            currentIndex = TextSearcher.indexOfMatch(atOrAfter: location, in: found)
            if let currentIndex { select(index: currentIndex) }
        } else if let previous = currentIndex, found.indices.contains(previous) {
            currentIndex = previous
        } else {
            currentIndex = nil
        }
        pushMatchesToView()
    }

    /// Waits for the in-flight search. Tests use this.
    func waitForSearch() async {
        await searchTask?.value
    }

    private func select(index: Int) {
        guard let textView, matches.indices.contains(index) else { return }
        currentIndex = index
        let match = matches[index]
        textView.setSelectedRange(match)
        textView.scrollRangeToVisible(match)
        textView.showFindIndicator(for: match)
        pushMatchesToView()
    }

    private func pushMatchesToView() {
        textView?.searchMatches = matches
        textView?.currentSearchMatch = currentIndex.flatMap { matches.indices.contains($0) ? matches[$0] : nil }
    }

    private func clearMatches() {
        matches = []
        currentIndex = nil
        errorMessage = nil
        pushMatchesToView()
    }

    private func selectedTextForSearch() -> String? {
        guard let textView else { return nil }
        let range = textView.selectedRange()
        guard range.length > 0, range.length <= 200 else { return nil }
        let text = textView.document.textStorage.mutableString.substring(with: range)
        guard !text.contains("\n") else { return nil }
        return text
    }

    private func observeStorage() {
        if let storageObserver {
            NotificationCenter.default.removeObserver(storageObserver)
            self.storageObserver = nil
        }
        guard let document = textView?.document else { return }
        storageObserver = NotificationCenter.default.addObserver(
            forName: Document.charactersDidChangeNotification, object: document, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.scheduleSearch()
            }
        }
    }
}
