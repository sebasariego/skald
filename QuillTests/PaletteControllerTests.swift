import XCTest
@testable import Quill

@MainActor
final class PaletteControllerTests: XCTestCase {
    private func candidates(_ titles: [String], onPick: @escaping @MainActor (String) -> Void = { _ in }) -> [PaletteCandidate] {
        titles.map { title in PaletteCandidate(id: title, title: title) { onPick(title) } }
    }

    func testEmptyQueryShowsCandidatesInOrder() async {
        let palette = PaletteController()
        palette.present(placeholder: "x", candidates: candidates(["b", "a", "c"]))
        await palette.waitForFilter()
        XCTAssertTrue(palette.isPresented)
        XCTAssertEqual(palette.results.map(\.id), ["b", "a", "c"])
    }

    func testQueryRanksAndHighlights() async {
        let palette = PaletteController()
        palette.present(placeholder: "x", candidates: candidates(["File: Save As\u{2026}", "File: Save", "View: Soft Wrap"]))
        palette.query = "save"
        await palette.waitForFilter()
        XCTAssertEqual(palette.results.map(\.id), ["File: Save", "File: Save As\u{2026}"])
        XCTAssertEqual(palette.results.first?.positions, [6, 7, 8, 9])
    }

    func testSelectionWrapsAndActivates() async {
        var picked: String?
        let palette = PaletteController()
        palette.present(placeholder: "x", candidates: candidates(["one", "two", "three"]) { picked = $0 })
        await palette.waitForFilter()
        palette.moveSelection(by: -1)
        XCTAssertEqual(palette.selectedIndex, 2)
        palette.moveSelection(by: 1)
        XCTAssertEqual(palette.selectedIndex, 0)
        palette.moveSelection(by: 1)
        palette.activateSelection()
        XCTAssertEqual(picked, "two")
        XCTAssertFalse(palette.isPresented)
        XCTAssertTrue(palette.results.isEmpty)
    }

    func testDisabledCandidatesDoNotRun() async {
        var ran = false
        let palette = PaletteController()
        palette.present(placeholder: "x", candidates: [PaletteCandidate(id: "d", title: "Disabled", isEnabled: false) { ran = true }])
        await palette.waitForFilter()
        palette.activateSelection()
        XCTAssertFalse(ran)
        XCTAssertTrue(palette.isPresented)
    }

    func testResultsAreCapped() async {
        let palette = PaletteController()
        palette.present(placeholder: "x", candidates: candidates((0..<200).map { "item \($0)" }))
        await palette.waitForFilter()
        XCTAssertEqual(palette.results.count, PaletteController.maximumResults)
    }
}
