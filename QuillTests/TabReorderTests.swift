import XCTest
@testable import Quill

@MainActor
final class TabReorderTests: XCTestCase {
    private func workspace() -> Workspace {
        let defaults = UserDefaults(suiteName: "dev.local.quill.tests.reorder") ?? .standard
        defaults.removePersistentDomain(forName: "dev.local.quill.tests.reorder")
        return Workspace(settingsStore: SettingsStore(defaults: defaults), sessionStore: SessionStore(defaults: defaults), themes: [ThemeLoader.fallbackTheme])
    }

    func testMoveBeforeTargetReordersTabs() {
        let workspace = workspace()
        let a = workspace.documents.newUntitled()
        let b = workspace.documents.newUntitled()
        let c = workspace.documents.newUntitled()
        workspace.moveTab(c.id, toIndex: 0)
        XCTAssertEqual(workspace.documents.documents.map(\.id), [c.id, a.id, b.id])
        workspace.moveTab(a.id, toIndex: 1) // already there
        XCTAssertEqual(workspace.documents.documents.map(\.id), [c.id, a.id, b.id])
        workspace.moveTab(c.id, toIndex: 2)
        XCTAssertEqual(workspace.documents.documents.map(\.id), [a.id, b.id, c.id])
        workspace.moveTab(a.id, toIndex: 99) // clamps to the end
        XCTAssertEqual(workspace.documents.documents.map(\.id), [b.id, c.id, a.id])
    }

    func testTerminalResolution() {
        let installed = ExternalTerminal.installed()
        XCTAssertTrue(installed.contains { $0.id == "com.apple.Terminal" }, "Terminal.app is always present")
        XCTAssertEqual(ExternalTerminal.resolve(preferredID: "com.apple.Terminal")?.id, "com.apple.Terminal")
        XCTAssertEqual(ExternalTerminal.resolve(preferredID: "nope.not.installed")?.id, installed.first?.id, "falls back to the first installed")
        XCTAssertEqual(ExternalTerminal.resolve(preferredID: nil)?.id, installed.first?.id)
    }

    func testTerminalDirectoryPrefersWorkingFolder() async throws {
        let directory = try TestTemporaryDirectory()
        defer { directory.remove() }
        let workspace = workspace()
        XCTAssertEqual(workspace.terminalDirectory, FileManager.default.homeDirectoryForCurrentUser)
        let file = try TestTemporaryDirectory().file("x.txt", contents: Data("x".utf8))
        await workspace.open(fileAt: file)
        XCTAssertEqual(workspace.terminalDirectory.standardizedFileURL, file.deletingLastPathComponent().standardizedFileURL, "no folder open: the file's folder")
        workspace.openFolder(at: directory.url)
        XCTAssertEqual(workspace.terminalDirectory.standardizedFileURL, directory.url.standardizedFileURL, "the working folder wins over the file's folder")
    }
}
