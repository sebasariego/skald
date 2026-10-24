import Foundation

/// Locates files in the repository, since the CLI test runner has no app bundle.
enum TestResources {
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    static func url(_ relativePath: String) -> URL {
        repositoryRoot.appendingPathComponent(relativePath)
    }
}
