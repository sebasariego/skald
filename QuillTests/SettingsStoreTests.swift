import XCTest
@testable import Quill

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "dev.local.quill.tests.settings"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultsWhenNothingSaved() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), .default)
    }

    func testRoundTrip() {
        let store = SettingsStore(defaults: defaults)
        var editor = EditorConfiguration()
        editor.fontSize = 17
        editor.fontName = "Menlo-Regular"
        editor.tabWidth = 2
        editor.insertSpaces = false
        editor.softWrap = false
        editor.trimTrailingWhitespaceOnSave = true
        store.save(SettingsStore.Snapshot(editor: editor, themeName: "Quill Light"))
        let loaded = store.load()
        XCTAssertEqual(loaded.editor, editor)
        XCTAssertEqual(loaded.themeName, "Quill Light")
    }

    func testCorruptDataFallsBackToDefaults() {
        defaults.set(Data("garbage".utf8), forKey: SettingsStore.key)
        XCTAssertEqual(SettingsStore(defaults: defaults).load(), .default)
    }

    @MainActor
    func testWorkspacePersistsChanges() throws {
        let dark = try ThemeLoader.load(from: TestResources.url("Quill/Resources/Themes/quill-dark.theme.json"))
        let light = try ThemeLoader.load(from: TestResources.url("Quill/Resources/Themes/quill-light.theme.json"))
        let store = SettingsStore(defaults: defaults)
        let workspace = Workspace(settingsStore: store, themes: [dark, light])
        XCTAssertEqual(workspace.theme.name, "Quill Dark")
        workspace.adjustFontSize(by: 3)
        workspace.selectTheme(named: "Quill Light")
        let saved = store.load()
        XCTAssertEqual(saved.editor.fontSize, 16)
        XCTAssertEqual(saved.themeName, "Quill Light")

        let reopened = Workspace(settingsStore: store, themes: [dark, light])
        XCTAssertEqual(reopened.theme.name, "Quill Light")
        XCTAssertEqual(reopened.editorConfiguration.fontSize, 16)
    }

    func testFontCatalogMapsSystemOption() {
        XCTAssertNil(MonospacedFontCatalog.fontName(forFamily: MonospacedFontCatalog.systemOption))
        XCTAssertEqual(MonospacedFontCatalog.family(forFontName: nil), MonospacedFontCatalog.systemOption)
        XCTAssertEqual(MonospacedFontCatalog.family(forFontName: "NoSuchFont-Regular"), MonospacedFontCatalog.systemOption)
        XCTAssertTrue(MonospacedFontCatalog.familyNames().contains("Menlo"))
    }
}
