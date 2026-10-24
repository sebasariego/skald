import XCTest
@testable import Quill

final class FileIconProviderTests: XCTestCase {
    func testGroupsFilesByKind() {
        XCTAssertEqual(FileIconProvider.symbolName(for: URL(fileURLWithPath: "/x/Sources"), isDirectory: true), "folder")
        XCTAssertEqual(FileIconProvider.symbolName(forExtension: "swift"), "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(FileIconProvider.symbolName(forExtension: "TSX"), "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(FileIconProvider.symbolName(forExtension: "sh"), "terminal")
        XCTAssertEqual(FileIconProvider.symbolName(forExtension: "json"), "curlybraces")
        XCTAssertEqual(FileIconProvider.symbolName(forExtension: "md"), "doc.text")
        XCTAssertEqual(FileIconProvider.symbolName(forExtension: "png"), "photo")
        XCTAssertEqual(FileIconProvider.symbolName(forExtension: "csv"), "tablecells")
        XCTAssertEqual(FileIconProvider.symbolName(forExtension: "pptx"), "rectangle.on.rectangle")
        XCTAssertEqual(FileIconProvider.symbolName(forExtension: "", fileName: ".zshrc"), "gearshape")
        XCTAssertEqual(FileIconProvider.symbolName(forExtension: "weird"), "doc")
    }

    func testEverySymbolExists() {
        let extensions = ["swift", "sh", "html", "css", "json", "xml", "md", "pdf", "docx", "xlsx", "pptx", "png", "svg", "mp3", "mp4", "zip", "ttf", "app", "xcodeproj", "nope"]
        for ext in extensions {
            let name = FileIconProvider.symbolName(forExtension: ext)
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "missing SF Symbol \(name) for .\(ext)")
        }
        XCTAssertNotNil(NSImage(systemSymbolName: FileIconProvider.folderSymbol, accessibilityDescription: nil))
    }
}
