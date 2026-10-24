import XCTest
@testable import Quill

final class TextFileCodecTests: XCTestCase {
    private var directory: TestTemporaryDirectory!

    override func setUpWithError() throws {
        directory = try TestTemporaryDirectory()
    }

    override func tearDown() {
        directory.remove()
    }

    func testReadsUTF8WithCRLFAndNormalizes() async throws {
        let url = try directory.file("a.txt", contents: Data("one\r\ntwo\r\n".utf8))
        let loaded = try await TextFileCodec.read(from: url)
        XCTAssertEqual(loaded.text, "one\ntwo\n")
        XCTAssertEqual(loaded.encoding, .utf8)
        XCTAssertEqual(loaded.lineEnding, .crlf)
        XCTAssertNotNil(loaded.modificationDate)
    }

    func testStripsUTF8BOM() async throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: "héllo".utf8)
        let url = try directory.file("bom.txt", contents: data)
        let loaded = try await TextFileCodec.read(from: url)
        XCTAssertEqual(loaded.text, "héllo")
    }

    func testFallsBackToLatin1() async throws {
        let url = try directory.file("latin.txt", contents: Data([0x63, 0x61, 0x66, 0xE9]))
        let loaded = try await TextFileCodec.read(from: url)
        XCTAssertEqual(loaded.text, "café")
        XCTAssertEqual(loaded.encoding, .isoLatin1)
    }

    func testRejectsBinary() async throws {
        let url = try directory.file("bin", contents: Data([0x00, 0x01, 0x02, 0x41]))
        do {
            _ = try await TextFileCodec.read(from: url)
            XCTFail("expected notText")
        } catch TextFileError.notText {
        }
    }

    func testWriteRestoresLineEndings() async throws {
        let url = directory.url.appendingPathComponent("out.txt")
        try await TextFileCodec.write("a\nb\n", to: url, encoding: .utf8, lineEnding: .crlf)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a\r\nb\r\n")
    }
}
