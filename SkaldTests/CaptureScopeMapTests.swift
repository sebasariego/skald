import XCTest
@testable import Skald

final class CaptureScopeMapTests: XCTestCase {
    private func theme(_ rules: [(String, String)]) -> Theme {
        Theme(
            name: "T", isDark: true, colors: ThemeColors(table: [:], isDark: true),
            tokenRules: rules.map { TokenColorRule(scopes: [$0.0], style: TokenStyle(foreground: HexColor.color(from: $0.1))) }
        )
    }

    func testPrefixes() {
        XCTAssertEqual(CaptureScopeMap.prefixes(of: "keyword.control.return"), ["keyword.control.return", "keyword.control", "keyword"])
    }

    func testSelectorMatchesOnDotBoundaries() {
        XCTAssertTrue(CaptureScopeMap.selector("keyword", matches: "keyword.control"))
        XCTAssertTrue(CaptureScopeMap.selector("keyword", matches: "keyword"))
        XCTAssertFalse(CaptureScopeMap.selector("keyword", matches: "keywords"))
        XCTAssertTrue(CaptureScopeMap.selector("source.swift keyword", matches: "keyword.control"))
    }

    func testLongestScopeWins() {
        let map = CaptureScopeMap(theme: theme([("keyword", "#111111"), ("keyword.control", "#222222")]))
        XCTAssertEqual(map.style(for: "keyword.control")?.foreground, HexColor.color(from: "#222222"))
        XCTAssertEqual(map.style(for: "keyword.function")?.foreground, HexColor.color(from: "#111111"))
    }

    func testCaptureFallsBackToParentCapture() {
        let map = CaptureScopeMap(theme: theme([("entity.name.function", "#333333")]))
        XCTAssertEqual(map.style(for: "function.method.call")?.foreground, HexColor.color(from: "#333333"))
        XCTAssertEqual(map.style(for: "function.builtin.weird")?.foreground, HexColor.color(from: "#333333"))
    }

    func testTranslatesTreeSitterCapturesToTextMateScopes() {
        let map = CaptureScopeMap(theme: theme([("constant.numeric", "#444444"), ("variable.language", "#555555"), ("comment", "#666666")]))
        XCTAssertEqual(map.style(for: "number")?.foreground, HexColor.color(from: "#444444"))
        XCTAssertEqual(map.style(for: "float")?.foreground, HexColor.color(from: "#444444"))
        XCTAssertEqual(map.style(for: "variable.builtin")?.foreground, HexColor.color(from: "#555555"))
        XCTAssertEqual(map.style(for: "comment.documentation")?.foreground, HexColor.color(from: "#666666"))
        XCTAssertNil(map.style(for: "spell"))
        XCTAssertNil(map.style(for: "unknown.capture"))
    }

    func testBundledThemesCoverCommonCaptures() throws {
        let theme = try ThemeLoader.load(from: TestResources.url("Skald/Resources/Themes/skald-dark.theme.json"))
        let map = CaptureScopeMap(theme: theme)
        for capture in ["keyword", "string", "comment", "number", "function", "type", "variable", "property", "operator", "punctuation.bracket", "attribute", "markup.heading", "text.title"] {
            XCTAssertNotNil(map.style(for: capture), "no style for \(capture)")
        }
    }
}
