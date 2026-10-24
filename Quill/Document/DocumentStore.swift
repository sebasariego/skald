import AppKit
import Observation

/// The only owner of `Document`s. Views and controllers borrow documents from here.
@MainActor
@Observable
final class DocumentStore {
    private(set) var documents: [Document] = []

    /// Called on the main actor when a document's file changed on disk and the
    /// change was not one of our own saves.
    var onExternalChange: (@MainActor (Document) -> Void)?

    /// The theme handed to new highlighters. `Workspace` keeps it current.
    var theme: Theme = ThemeLoader.fallbackTheme {
        didSet {
            for document in documents {
                document.highlighter?.theme = theme
            }
        }
    }

    func document(withID id: Document.ID) -> Document? {
        documents.first { $0.id == id }
    }

    func document(for url: URL) -> Document? {
        let standardized = url.standardizedFileURL
        return documents.first { $0.url?.standardizedFileURL == standardized }
    }

    /// Opens `url`, or returns the already-open document for it.
    func open(_ url: URL) async throws -> Document {
        if let existing = document(for: url) { return existing }
        let loaded = try await TextFileCodec.read(from: url)
        if let existing = document(for: url) { return existing } // opened concurrently
        let document = Document(
            url: url,
            text: loaded.text,
            encoding: loaded.encoding,
            lineEnding: loaded.lineEnding,
            modificationDate: loaded.modificationDate,
            lineIndex: loaded.lineIndex
        )
        document.updateLanguage(theme: theme)
        monitor(document)
        documents.append(document)
        return document
    }

    func newUntitled() -> Document {
        let document = Document(url: nil)
        documents.append(document)
        return document
    }

    /// Writes the document to `url`, or to its own URL when `url` is nil.
    /// `editor` is the text view showing the document, if any; trimming through it keeps the trim undoable.
    func save(_ document: Document, to url: URL? = nil, trimmingTrailingWhitespace: Bool = false, editor: NSTextView? = nil) async throws {
        guard let target = url ?? document.url else { return }
        if trimmingTrailingWhitespace {
            if let editor, editor.textStorage === document.textStorage {
                TrailingWhitespaceTrimmer.trim(in: editor)
            } else {
                TrailingWhitespaceTrimmer.trim(document.textStorage)
            }
        }
        let text = document.text
        try await TextFileCodec.write(text, to: target, encoding: document.encoding, lineEnding: document.lineEnding)
        let date = try? target.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        document.markSaved(to: target, modificationDate: date)
        document.updateLanguage(theme: theme)
        monitor(document)
    }

    /// Re-reads the document from disk, discarding in-memory edits.
    func reload(_ document: Document) async throws {
        guard let url = document.url else { return }
        let loaded = try await TextFileCodec.read(from: url)
        document.replaceText(with: loaded.text, encoding: loaded.encoding, lineEnding: loaded.lineEnding, modificationDate: loaded.modificationDate, lineIndex: loaded.lineIndex)
    }

    func close(_ document: Document) {
        document.stopMonitoring()
        documents.removeAll { $0.id == document.id }
    }

    private func monitor(_ document: Document) {
        document.startMonitoring { [weak self, weak document] in
            guard let self, let document, self.documents.contains(where: { $0 === document }) else { return }
            self.fileDidChange(document)
        }
    }

    private func fileDidChange(_ document: Document) {
        let onDisk = document.modificationDateOnDisk
        // Our own save already recorded the new date; identical dates mean nothing to do.
        if let onDisk, let known = document.lastKnownModificationDate, abs(onDisk.timeIntervalSince(known)) < 0.001 {
            return
        }
        guard onDisk != nil else { return } // deleted or mid-replace; the monitor re-arms
        onExternalChange?(document)
    }
}
