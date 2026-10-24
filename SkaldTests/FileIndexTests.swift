import XCTest
@testable import Skald

final class FileIndexTests: XCTestCase {
    func testScanSkipsIgnoredAndHiddenDirectories() async throws {
        let directory = try TestTemporaryDirectory()
        defer { directory.remove() }
        let root = directory.url
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root.appendingPathComponent("src/deep"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: root.appendingPathComponent("src/deep/main.swift"))
        try Data("b".utf8).write(to: root.appendingPathComponent("src/README.md"))
        try Data("c".utf8).write(to: root.appendingPathComponent("node_modules/pkg/index.js"))
        try Data("d".utf8).write(to: root.appendingPathComponent(".git/HEAD"))
        try Data("e".utf8).write(to: root.appendingPathComponent(".hidden"))

        let entries = await FileIndex.scan(root)
        XCTAssertEqual(entries.map(\.relativePath), ["src/deep/main.swift", "src/README.md"])
        XCTAssertEqual(entries.first?.fileName, "main.swift")
        XCTAssertEqual(entries.first?.directory, "src/deep")
    }

    @MainActor
    func testSetRootIndexesAsynchronously() async throws {
        let directory = try TestTemporaryDirectory()
        defer { directory.remove() }
        try Data("x".utf8).write(to: directory.url.appendingPathComponent("one.txt"))
        let index = FileIndex()
        index.setRoot(directory.url)
        XCTAssertTrue(index.isIndexing)
        for _ in 0..<100 where index.isIndexing {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(index.isIndexing)
        XCTAssertEqual(index.entries.map(\.relativePath), ["one.txt"])
        index.setRoot(nil)
        XCTAssertTrue(index.entries.isEmpty)
    }
}
