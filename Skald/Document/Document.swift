import AppKit
import Observation

/// One open file. Owns the text storage and the undo stack so both survive
/// the editor view being torn down and rebuilt when tabs switch.
@MainActor
@Observable
final class Document: Identifiable {
    /// Posted with the document as object after characters change (not on attribute-only edits).
    static let charactersDidChangeNotification = Notification.Name("dev.local.skald.document.charactersDidChange")

    let id = UUID()
    private(set) var url: URL?
    private(set) var isDirty = false
    private(set) var encoding: String.Encoding
    private(set) var lineEnding: LineEnding
    private(set) var lastKnownModificationDate: Date?

    /// Set by `DocumentStore` from the file name; nil means plain text.
    private(set) var language: LanguageDefinition?
    /// Present when a parser exists for `language`.
    @ObservationIgnored private(set) var highlighter: SyntaxHighlighter?

    @ObservationIgnored let textStorage: NSTextStorage
    @ObservationIgnored let undoManager = UndoManager()
    /// Line starts, maintained incrementally. Read it from the main actor only.
    @ObservationIgnored private(set) var lineIndex: LineIndex
    @ObservationIgnored private let observer = TextStorageObserver()
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var changeMonitor: FileChangeMonitor?
    /// Hash of the text as last loaded or saved; undo/redo compare against it.
    @ObservationIgnored private var savedTextHash: Int
    @ObservationIgnored private var undoObservers: [NSObjectProtocol] = []

    init(url: URL?, text: String = "", encoding: String.Encoding = .utf8, lineEnding: LineEnding = .lf, modificationDate: Date? = nil, lineIndex: LineIndex? = nil) {
        self.url = url
        self.encoding = encoding
        self.lineEnding = lineEnding
        self.lastKnownModificationDate = modificationDate
        textStorage = NSTextStorage(string: text)
        self.lineIndex = lineIndex ?? LineIndex(text: textStorage.mutableString)
        savedTextHash = Self.hash(of: textStorage.mutableString)
        undoManager.levelsOfUndo = 0 // unlimited
        textStorage.delegate = observer
        observeUndo()
        observer.onCharactersChanged = { [weak self] editedRange, delta in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.charactersDidChange(in: editedRange, delta: delta)
            }
        }
    }

    private func charactersDidChange(in editedRange: NSRange, delta: Int) {
        let oldRange = NSRange(location: editedRange.location, length: editedRange.length - delta)
        let newText = textStorage.mutableString.substring(with: editedRange) as NSString
        let startPoint = lineIndex.point(forOffset: oldRange.location)
        let oldEndPoint = lineIndex.point(forOffset: NSMaxRange(oldRange))
        lineIndex.replaceCharacters(in: oldRange, with: newText)
        let newEndPoint = lineIndex.point(forOffset: NSMaxRange(editedRange))
        if !isLoading {
            isDirty = true
            let edit = TextEdit(
                startOffset: oldRange.location,
                oldEndOffset: NSMaxRange(oldRange),
                newEndOffset: NSMaxRange(editedRange),
                startPoint: startPoint,
                oldEndPoint: oldEndPoint,
                newEndPoint: newEndPoint
            )
            highlighter?.documentDidChange(edit)
        }
        NotificationCenter.default.post(name: Self.charactersDidChangeNotification, object: self)
    }

    deinit {
        for observer in undoObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// After undo or redo, dirty means "differs from what is on disk", not "was edited".
    private func observeUndo() {
        for name in [NSNotification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: undoManager, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.recomputeDirtyAfterUndo() }
            }
            undoObservers.append(observer)
        }
    }

    private func recomputeDirtyAfterUndo() {
        isDirty = Self.hash(of: textStorage.mutableString) != savedTextHash
    }

    /// Hashes the text in UTF-16 chunks; a few milliseconds for 5 MB, paid only on load, save, undo and redo.
    nonisolated static func hash(of text: NSString) -> Int {
        var hasher = Hasher()
        let length = text.length
        hasher.combine(length)
        var buffer = [unichar](repeating: 0, count: min(length, 1 << 15))
        var position = 0
        while position < length {
            let chunk = NSRange(location: position, length: min(buffer.count, length - position))
            text.getCharacters(&buffer, range: chunk)
            buffer.withUnsafeBufferPointer { pointer in
                hasher.combine(bytes: UnsafeRawBufferPointer(start: pointer.baseAddress, count: chunk.length * 2))
            }
            position += chunk.length
        }
        return hasher.finalize()
    }

    /// An immutable copy of the text for background work.
    func snapshot() -> TextSnapshot {
        TextSnapshot(textStorage.mutableString)
    }

    /// Picks the language for the current URL and (re)creates the highlighter.
    func updateLanguage(theme: Theme) {
        let detected = url.flatMap(LanguageRegistry.language(for:))
        guard detected != language || (detected != nil && highlighter == nil) else {
            highlighter?.theme = theme
            return
        }
        language = detected
        if let detected, let parser = LanguageRegistry.makeParser(for: detected) {
            highlighter = SyntaxHighlighter(language: detected, parser: parser, document: self, theme: theme)
        } else {
            highlighter = nil
        }
    }

    var displayName: String {
        url?.lastPathComponent ?? "Untitled"
    }

    var fileExtension: String {
        url?.pathExtension.lowercased() ?? ""
    }

    /// The whole text, LF-normalized. Copying 5 MB is cheap compared with disk I/O.
    var text: String {
        textStorage.string
    }

    /// Replaces the contents without touching the dirty flag or undo stack.
    func replaceText(with text: String, encoding: String.Encoding, lineEnding: LineEnding, modificationDate: Date?, lineIndex: LineIndex? = nil) {
        isLoading = true
        defer { isLoading = false }
        undoManager.removeAllActions()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: text)
        if let lineIndex { self.lineIndex = lineIndex }
        self.encoding = encoding
        self.lineEnding = lineEnding
        self.lastKnownModificationDate = modificationDate
        savedTextHash = Self.hash(of: textStorage.mutableString)
        isDirty = false
        highlighter?.documentDidReplaceText()
    }

    /// Watches the file on disk and calls `handler` on the main actor when it changes.
    func startMonitoring(onChange handler: @escaping @MainActor @Sendable () -> Void) {
        changeMonitor?.cancel()
        changeMonitor = nil
        guard let url else { return }
        changeMonitor = FileChangeMonitor(url: url, onChange: handler)
    }

    func stopMonitoring() {
        changeMonitor?.cancel()
        changeMonitor = nil
    }

    /// Accept the on-disk version as known without reloading ("keep my changes").
    func acknowledgeExternalChange(modificationDate: Date?) {
        lastKnownModificationDate = modificationDate
    }

    /// Current modification date on disk, or nil when the file is missing.
    var modificationDateOnDisk: Date? {
        guard let url else { return nil }
        return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Lets tests supply a parser without going through `LanguageRegistry`.
    func installHighlighterForTesting(_ highlighter: SyntaxHighlighter) {
        self.highlighter = highlighter
    }

    func markSaved(to url: URL, modificationDate: Date?) {
        self.url = url
        self.lastKnownModificationDate = modificationDate
        savedTextHash = Self.hash(of: textStorage.mutableString)
        isDirty = false
    }
}
