import XCTest
@testable import Quill

final class ThemeLoaderTests: XCTestCase {
    func testLoadsBundledDarkTheme() throws {
        let theme = try ThemeLoader.load(from: TestResources.url("Quill/Resources/Themes/quill-dark.theme.json"))
        XCTAssertEqual(theme.name, "Quill Dark")
        XCTAssertTrue(theme.isDark)
        XCTAssertFalse(theme.tokenRules.isEmpty)
        XCTAssertEqual(theme.colors.editorBackground, HexColor.color(from: "#1E1F24"))
    }

    func testLoadsBundledLightTheme() throws {
        let theme = try ThemeLoader.load(from: TestResources.url("Quill/Resources/Themes/quill-light.theme.json"))
        XCTAssertEqual(theme.name, "Quill Light")
        XCTAssertFalse(theme.isDark)
    }

    func testParsesScopeVariants() throws {
        let json = """
        { "name": "T", "type": "light", "tokenColors": [
            { "scope": "comment, string", "settings": { "foreground": "#112233" } },
            { "scope": ["keyword", "storage"], "settings": { "fontStyle": "bold italic" } },
            { "scope": "ignored", "settings": {} }
        ] }
        """
        let theme = try ThemeLoader.load(data: Data(json.utf8), fallbackName: "x")
        XCTAssertEqual(theme.tokenRules.count, 2)
        XCTAssertEqual(theme.tokenRules[0].scopes, ["comment", "string"])
        XCTAssertEqual(theme.tokenRules[1].scopes, ["keyword", "storage"])
        XCTAssertTrue(theme.tokenRules[1].style.bold)
        XCTAssertTrue(theme.tokenRules[1].style.italic)
        XCTAssertNil(theme.tokenRules[1].style.foreground)
    }

    func testRejectsMalformedJSON() {
        XCTAssertThrowsError(try ThemeLoader.load(data: Data("{ nope".utf8), fallbackName: "x"))
    }

    func testHexColors() throws {
        let rgb = try XCTUnwrap(HexColor.color(from: "#FF8000"))
        XCTAssertEqual(rgb.redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(rgb.greenComponent, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(rgb.alphaComponent, 1)
        let rgba = try XCTUnwrap(HexColor.color(from: "#00000080"))
        XCTAssertEqual(rgba.alphaComponent, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(HexColor.color(from: "#abc")?.blueComponent ?? 0, 0xCC / 255.0, accuracy: 0.001)
        XCTAssertNil(HexColor.color(from: "red"))
    }
}
