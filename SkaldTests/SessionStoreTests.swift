import XCTest
@testable import Skald

final class SessionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "dev.local.skald.tests.session"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testBookmarkRoundTrip() throws {
        let directory = try TestTemporaryDirectory()
        defer { directory.remove() }
        let url = try directory.file("a.txt", contents: Data("x".utf8))
        let bookmark = try XCTUnwrap(SessionStore.bookmark(for: url))
        let resolved = try XCTUnwrap(SessionStore.resolve(bookmark))
        XCTAssertEqual(resolved.standardizedFileURL.resolvingSymlinksInPath(), url.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testResolveReturnsNilForMissingFile() throws {
        let directory = try TestTemporaryDirectory()
        let url = try directory.file("gone.txt", contents: Data("x".utf8))
        let bookmark = try XCTUnwrap(SessionStore.bookmark(for: url))
        directory.remove()
        XCTAssertNil(SessionStore.resolve(bookmark))
    }

    func testSaveAndLoad() {
        let store = SessionStore(defaults: defaults)
        XCTAssertNil(store.load())
        let state = SessionState(folderBookmark: Data([1, 2]), fileBookmarks: [Data([3])], selectedIndex: 0)
        store.save(state)
        XCTAssertEqual(store.load(), state)
        store.clear()
        XCTAssertNil(store.load())
    }

    @MainActor
    func testWorkspaceSavesAndRestoresSession() async throws {
        let directory = try TestTemporaryDirectory()
        defer { directory.remove() }
        let fileA = try directory.file("a.swift", contents: Data("let a = 1".utf8))
        let fileB = try directory.file("b.md", contents: Data("# b".utf8))
        let settings = SettingsStore(defaults: defaults, legacyDefaults: nil)
        let sessions = SessionStore(defaults: defaults)
        let theme = ThemeLoader.fallbackTheme

        let first = Workspace(settingsStore: settings, sessionStore: sessions, themes: [theme])
        first.openFolder(at: directory.url)
        await first.open(fileAt: fileA)
        await first.open(fileAt: fileB)
        first.selectedDocumentID = first.documents.documents.first?.id
        let saved = try XCTUnwrap(sessions.load())
        XCTAssertNotNil(saved.folderBookmark)
        XCTAssertEqual(saved.fileBookmarks.count, 2)
        XCTAssertEqual(saved.selectedIndex, 0)

        let second = Workspace(settingsStore: settings, sessionStore: sessions, themes: [theme])
        second.restoreSession()
        for _ in 0..<100 where second.documents.documents.count < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(second.folderTree.root?.url.lastPathComponent, directory.url.lastPathComponent)
        XCTAssertEqual(second.documents.documents.map { $0.url?.lastPathComponent }, ["a.swift", "b.md"])
        XCTAssertEqual(second.selectedDocument?.displayName, "a.swift")
    }
}
