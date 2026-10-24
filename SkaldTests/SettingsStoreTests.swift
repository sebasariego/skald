import XCTest
@testable import Skald

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "dev.local.skald.tests.settings"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultsWhenNothingSaved() {
        let store = SettingsStore(defaults: defaults, legacyDefaults: nil)
        XCTAssertEqual(store.load(), .default)
    }

    func testRoundTrip() {
        let store = SettingsStore(defaults: defaults, legacyDefaults: nil)
        var editor = EditorConfiguration()
        editor.fontSize = 17
        editor.fontName = "Menlo-Regular"
        editor.tabWidth = 2
        editor.insertSpaces = false
        editor.softWrap = false
        editor.trimTrailingWhitespaceOnSave = true
        store.save(SettingsStore.Snapshot(editor: editor, themeName: "Skald Light"))
        let loaded = store.load()
        XCTAssertEqual(loaded.editor, editor)
        XCTAssertEqual(loaded.themeName, "Skald Light")
    }

    func testLegacyQuillKeyIsAdoptedAndRewritten() {
        var editor = EditorConfiguration()
        editor.fontSize = 19
        let legacy = SettingsStore.Snapshot(editor: editor, themeName: "Quill Light")
        defaults.set(try? JSONEncoder().encode(legacy), forKey: SettingsStore.legacyKey)
        let store = SettingsStore(defaults: defaults, legacyDefaults: nil)
        XCTAssertEqual(store.load().editor.fontSize, 19)
        XCTAssertNotNil(defaults.data(forKey: SettingsStore.key), "adopted settings are saved under the new key")
    }

    func testLegacySuiteIsAdopted() {
        let legacySuite = "dev.local.skald.tests.legacy-suite"
        let legacyDefaults = UserDefaults(suiteName: legacySuite)
        legacyDefaults?.removePersistentDomain(forName: legacySuite)
        defer { legacyDefaults?.removePersistentDomain(forName: legacySuite) }
        var editor = EditorConfiguration()
        editor.tabWidth = 3
        legacyDefaults?.set(try? JSONEncoder().encode(SettingsStore.Snapshot(editor: editor, themeName: nil)), forKey: SettingsStore.legacyKey)
        let store = SettingsStore(defaults: defaults, legacyDefaults: legacyDefaults)
        XCTAssertEqual(store.load().editor.tabWidth, 3)
    }

    @MainActor
    func testLegacyThemeNameMapsToRenamedTheme() throws {
        let dark = try ThemeLoader.load(from: TestResources.url("Skald/Resources/Themes/skald-dark.theme.json"))
        let light = try ThemeLoader.load(from: TestResources.url("Skald/Resources/Themes/skald-light.theme.json"))
        let store = SettingsStore(defaults: defaults, legacyDefaults: nil)
        store.save(SettingsStore.Snapshot(editor: EditorConfiguration(), themeName: "Quill Light"))
        let workspace = Workspace(settingsStore: store, themes: [dark, light])
        XCTAssertEqual(workspace.theme.name, "Skald Light")
    }

    func testCorruptDataFallsBackToDefaults() {
        defaults.set(Data("garbage".utf8), forKey: SettingsStore.key)
        XCTAssertEqual(SettingsStore(defaults: defaults, legacyDefaults: nil).load(), .default)
    }

    @MainActor
    func testWorkspacePersistsChanges() throws {
        let dark = try ThemeLoader.load(from: TestResources.url("Skald/Resources/Themes/skald-dark.theme.json"))
        let light = try ThemeLoader.load(from: TestResources.url("Skald/Resources/Themes/skald-light.theme.json"))
        let store = SettingsStore(defaults: defaults, legacyDefaults: nil)
        let workspace = Workspace(settingsStore: store, themes: [dark, light])
        XCTAssertEqual(workspace.theme.name, "Skald Dark")
        workspace.adjustFontSize(by: 3)
        workspace.selectTheme(named: "Skald Light")
        let saved = store.load()
        XCTAssertEqual(saved.editor.fontSize, 16)
        XCTAssertEqual(saved.themeName, "Skald Light")

        let reopened = Workspace(settingsStore: store, themes: [dark, light])
        XCTAssertEqual(reopened.theme.name, "Skald Light")
        XCTAssertEqual(reopened.editorConfiguration.fontSize, 16)
    }

    func testFontCatalogMapsSystemOption() {
        XCTAssertNil(MonospacedFontCatalog.fontName(forFamily: MonospacedFontCatalog.systemOption))
        XCTAssertEqual(MonospacedFontCatalog.family(forFontName: nil), MonospacedFontCatalog.systemOption)
        XCTAssertEqual(MonospacedFontCatalog.family(forFontName: "NoSuchFont-Regular"), MonospacedFontCatalog.systemOption)
        XCTAssertTrue(MonospacedFontCatalog.familyNames().contains("Menlo"))
    }
}
