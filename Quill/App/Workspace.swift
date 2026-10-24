import AppKit
import Observation

/// Single-window state: the open folder, the open documents and which one is showing.
/// Views read from here; file and text ownership lives in `DocumentStore`.
@MainActor
@Observable
final class Workspace {
    let documents = DocumentStore()
    let folderTree = FolderTree()
    let find = FindController()
    let status = EditorStatus()
    let palette = PaletteController()
    let fileIndex = FileIndex()
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let sessionStore: SessionStore
    @ObservationIgnored private var isRestoringSession = false
    var editorConfiguration: EditorConfiguration {
        didSet { if editorConfiguration != oldValue { persistSettings() } }
    }

    /// The text view currently on screen. Views never own text; this is only a handle for commands.
    @ObservationIgnored private(set) weak var activeTextView: CodeTextView?

    private func editor(for document: Document) -> CodeTextView? {
        guard let activeTextView, activeTextView.document === document else { return nil }
        return activeTextView
    }

    func editorDidAppear(_ textView: CodeTextView) {
        activeTextView = textView
        find.attach(textView)
        status.track(textView)
        // The window is not attached yet during view creation; focus on the next turn.
        DispatchQueue.main.async { [weak textView] in
            guard let textView, let window = textView.window, !self.find.isVisible else { return }
            window.makeFirstResponder(textView)
        }
    }

    var selectedDocumentID: Document.ID? {
        didSet { if selectedDocumentID != oldValue { saveSession() } }
    }
    var presentedError: PresentedError?

    let availableThemes: [Theme]
    var theme: Theme {
        didSet {
            documents.theme = theme
            NSApplication.shared.appearance = theme.appearance
            if theme != oldValue { persistSettings() }
        }
    }

    init(settingsStore: SettingsStore = SettingsStore(), sessionStore: SessionStore = SessionStore(), themes: [Theme]? = nil) {
        self.settingsStore = settingsStore
        self.sessionStore = sessionStore
        let saved = settingsStore.load()
        let bundled = themes ?? ThemeLoader.bundledThemes()
        availableThemes = bundled
        editorConfiguration = saved.editor
        theme = bundled.first { $0.name == saved.themeName }
            ?? bundled.first { $0.name == "Quill Dark" }
            ?? bundled.first
            ?? ThemeLoader.fallbackTheme
        documents.theme = theme
        NSApplication.shared.appearance = theme.appearance
        documents.onExternalChange = { [weak self] document in
            self?.handleExternalChange(of: document)
        }
    }

    // MARK: External changes

    private func handleExternalChange(of document: Document) {
        if document.isDirty {
            switch ExternalChangePrompt.run(for: document) {
            case .reload:
                Task { await reload(document) }
            case .keepMine:
                document.acknowledgeExternalChange(modificationDate: document.modificationDateOnDisk)
            }
        } else {
            Task { await reload(document) }
        }
    }

    private func reload(_ document: Document) async {
        do {
            try await documents.reload(document)
        } catch {
            present(error, title: "Couldn't reload \(document.displayName)")
        }
    }

    // MARK: Session

    /// Reopens the last folder and files. Call once at launch.
    func restoreSession() {
        guard let state = sessionStore.load() else { return }
        isRestoringSession = true
        if let bookmark = state.folderBookmark, let folder = SessionStore.resolve(bookmark) {
            openFolder(at: folder)
        }
        let urls = state.fileBookmarks.compactMap(SessionStore.resolve)
        Task { @MainActor in
            var opened: [Document] = []
            for url in urls {
                if let document = try? await documents.open(url) { opened.append(document) }
            }
            if let index = state.selectedIndex, opened.indices.contains(index) {
                selectedDocumentID = opened[index].id
            } else {
                selectedDocumentID = opened.last?.id
            }
            isRestoringSession = false
            saveSession()
        }
    }

    func saveSession() {
        guard !isRestoringSession else { return }
        let files = documents.documents.compactMap(\.url)
        let selected = selectedDocument?.url.flatMap { url in files.firstIndex(of: url) }
        let state = SessionState(
            folderBookmark: folderTree.root.flatMap { SessionStore.bookmark(for: $0.url) },
            fileBookmarks: files.compactMap(SessionStore.bookmark(for:)),
            selectedIndex: selected
        )
        sessionStore.save(state)
    }

    /// Files or folders handed over by Finder or a Dock drop.
    func open(urls: [URL]) {
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                openFolder(at: url)
            } else {
                Task { await open(fileAt: url) }
            }
        }
    }

    private func persistSettings() {
        settingsStore.save(SettingsStore.Snapshot(editor: editorConfiguration, themeName: theme.name))
    }

    func selectTheme(named name: String) {
        guard let match = availableThemes.first(where: { $0.name == name }) else { return }
        theme = match
    }

    var selectedDocument: Document? {
        guard let selectedDocumentID else { return nil }
        return documents.document(withID: selectedDocumentID)
    }

    // MARK: Folder

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFolder(at: url)
    }

    func openFolder(at url: URL) {
        folderTree.open(url)
        fileIndex.setRoot(url)
        saveSession()
    }

    // MARK: Palette

    func showCommandPalette() {
        let candidates = CommandRegistry.commands(for: self).map { command in
            PaletteCandidate(id: command.id, title: command.title, detail: command.shortcut, isEnabled: command.isEnabled, perform: command.perform)
        }
        palette.present(placeholder: "Type a command", candidates: candidates)
    }

    func showQuickOpen() {
        guard fileIndex.rootURL != nil else {
            openFolderPanel()
            return
        }
        palette.present(placeholder: "Go to file in \(folderTree.root?.name ?? "folder")", candidates: fileCandidates())
        fileIndex.refresh()
        Task { [weak self] in
            // When the refresh lands, swap in the fresh list without closing the palette.
            guard let self else { return }
            while self.fileIndex.isIndexing { try? await Task.sleep(for: .milliseconds(50)) }
            self.palette.updateCandidates(self.fileCandidates())
        }
    }

    private func fileCandidates() -> [PaletteCandidate] {
        fileIndex.entries.map { entry in
            PaletteCandidate(
                id: entry.relativePath,
                title: entry.relativePath,
                subtitle: nil,
                searchBuffer: entry.searchBuffer,
                originalBuffer: entry.originalBuffer
            ) { [weak self] in
                Task { await self?.open(fileAt: entry.url) }
            }
        }
    }

    func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // MARK: Files

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            Task { await open(fileAt: url) }
        }
    }

    func open(fileAt url: URL) async {
        do {
            let document = try await documents.open(url)
            selectedDocumentID = document.id
            saveSession()
        } catch {
            present(error, title: "Couldn't open \(url.lastPathComponent)")
        }
    }

    func newDocument() {
        let document = documents.newUntitled()
        selectedDocumentID = document.id
    }

    func save() async {
        guard let document = selectedDocument else { return }
        await save(document)
    }

    func saveAs() async {
        guard let document = selectedDocument else { return }
        await saveAs(document)
    }

    /// Returns `true` when the document was written.
    @discardableResult
    func save(_ document: Document) async -> Bool {
        guard document.url != nil else { return await saveAs(document) }
        do {
            try await documents.save(document, trimmingTrailingWhitespace: editorConfiguration.trimTrailingWhitespaceOnSave, editor: editor(for: document))
            return true
        } catch {
            present(error, title: "Couldn't save \(document.displayName)")
            return false
        }
    }

    @discardableResult
    func saveAs(_ document: Document) async -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.displayName
        panel.directoryURL = document.url?.deletingLastPathComponent() ?? folderTree.root?.url
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try await documents.save(document, to: url, trimmingTrailingWhitespace: editorConfiguration.trimTrailingWhitespaceOnSave, editor: editor(for: document))
            if let view = activeTextView, view.document === document {
                view.apply(editorConfiguration, theme: theme) // picks up a highlighter for the new extension
            }
            return true
        } catch {
            present(error, title: "Couldn't save \(url.lastPathComponent)")
            return false
        }
    }

    // MARK: Tabs

    func selectTab(at index: Int) {
        let documents = documents.documents
        guard documents.indices.contains(index) else { return }
        selectedDocumentID = documents[index].id
    }

    func selectAdjacentTab(offset: Int) {
        let documents = documents.documents
        guard !documents.isEmpty else { return }
        let current = documents.firstIndex { $0.id == selectedDocumentID } ?? 0
        selectedDocumentID = documents[(current + offset + documents.count) % documents.count].id
    }

    func closeSelectedTab() {
        guard let document = selectedDocument else { return }
        Task { await close(document) }
    }

    func close(_ document: Document) async {
        if document.isDirty {
            switch UnsavedChangesPrompt.run(for: document) {
            case .save:
                guard await save(document) else { return }
            case .discard:
                break
            case .cancel:
                return
            }
        }
        let wasSelected = document.id == selectedDocumentID
        let index = documents.documents.firstIndex(where: { $0.id == document.id })
        documents.close(document)
        defer { saveSession() }
        if wasSelected {
            let remaining = documents.documents
            if remaining.isEmpty {
                selectedDocumentID = nil
                find.attach(nil)
                find.hide()
                status.clear()
            } else {
                let next = min(index ?? 0, remaining.count - 1)
                selectedDocumentID = remaining[next].id
            }
        }
    }

    // MARK: Find

    func showFind(withReplace: Bool) {
        guard selectedDocument != nil else { return }
        find.attach(activeTextView)
        find.show(withReplace: withReplace)
    }

    // MARK: Editor settings

    func toggleSoftWrap() {
        editorConfiguration.softWrap.toggle()
    }

    func toggleLineNumbers() {
        editorConfiguration.showLineNumbers.toggle()
    }

    func adjustFontSize(by delta: CGFloat) {
        editorConfiguration.adjustFontSize(by: delta)
    }

    func resetFontSize() {
        editorConfiguration.fontSize = EditorConfiguration().fontSize
    }

    // MARK: Errors

    private func present(_ error: Error, title: String) {
        presentedError = PresentedError(title: title, message: error.localizedDescription)
    }
}
