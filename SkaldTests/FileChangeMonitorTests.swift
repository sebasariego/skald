import XCTest
@testable import Skald

final class FileChangeMonitorTests: XCTestCase {
    func testReportsExternalWrite() async throws {
        let directory = try TestTemporaryDirectory()
        defer { directory.remove() }
        let url = try directory.file("watched.txt", contents: Data("one".utf8))

        let changed = expectation(description: "change reported")
        changed.assertForOverFulfill = false
        let monitor = FileChangeMonitor(url: url) { changed.fulfill() }
        try await Task.sleep(for: .milliseconds(150))
        try Data("two".utf8).write(to: url)
        await fulfillment(of: [changed], timeout: 3)
        monitor.cancel()
    }

    func testSurvivesAtomicReplace() async throws {
        let directory = try TestTemporaryDirectory()
        defer { directory.remove() }
        let url = try directory.file("replaced.txt", contents: Data("a".utf8))

        let counter = Counter()
        let monitor = FileChangeMonitor(url: url) {
            counter.increment()
        }
        try await Task.sleep(for: .milliseconds(150))
        // Replace the inode the way other editors do, wait for re-arm, then write in place.
        try await TextFileCodec.write("b", to: url, encoding: .utf8, lineEnding: .lf)
        try await Task.sleep(for: .milliseconds(900))
        try Data("c".utf8).write(to: url)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertGreaterThanOrEqual(counter.value, 2, "expected a report for the replace and one for the later write")
        monitor.cancel()
    }

    private final class Counter: @unchecked Sendable {
        private var count = 0
        private let lock = NSLock()
        var value: Int { lock.withLock { count } }
        func increment() { lock.withLock { count += 1 } }
    }
}
