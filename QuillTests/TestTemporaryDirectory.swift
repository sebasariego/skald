import Foundation

/// A fresh scratch folder per test, under the process temp dir.
struct TestTemporaryDirectory {
    let url: URL

    init() throws {
        let base = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        url = base.appendingPathComponent("QuillTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String, contents: Data) throws -> URL {
        let fileURL = url.appendingPathComponent(name)
        try contents.write(to: fileURL)
        return fileURL
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
