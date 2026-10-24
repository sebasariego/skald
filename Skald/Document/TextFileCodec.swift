import Foundation

/// A decoded text file plus what is needed to write it back the same way.
struct LoadedTextFile: Sendable {
    var text: String
    var encoding: String.Encoding
    var lineEnding: LineEnding
    var modificationDate: Date?
    /// Computed while still off the main actor so opening a large file stays quick.
    var lineIndex: LineIndex
}

enum TextFileError: LocalizedError {
    case notText
    case undecodable

    var errorDescription: String? {
        switch self {
        case .notText: return "The file does not appear to be a text file."
        case .undecodable: return "The file's text encoding could not be determined."
        }
    }
}

/// Reads and writes text files. Every function here is free of UI and runs off the main actor.
enum TextFileCodec {
    static func read(from url: URL) async throws -> LoadedTextFile {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let modificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let (rawText, encoding) = try decode(data)
        let lineEnding = LineEnding.detect(in: rawText)
        let text = LineEnding.normalizeToLF(rawText)
        return LoadedTextFile(
            text: text,
            encoding: encoding,
            lineEnding: lineEnding,
            modificationDate: modificationDate,
            lineIndex: LineIndex(text: text as NSString)
        )
    }

    /// Writes `text` (LF-normalized) using the given convention.
    ///
    /// The data goes to a hidden sibling file first and is then renamed over the
    /// target, so a crash mid-write never leaves a truncated file. Permissions of
    /// an existing file are carried over.
    static func write(_ text: String, to url: URL, encoding: String.Encoding, lineEnding: LineEnding) async throws {
        let onDisk = lineEnding.apply(to: text)
        guard let data = onDisk.data(using: encoding) ?? onDisk.data(using: .utf8) else {
            throw TextFileError.undecodable
        }
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.prefix(8)).skald-tmp")
        try data.write(to: temporaryURL)
        if let permissions = try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] {
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporaryURL.path)
        }
        guard rename(temporaryURL.path, url.path) == 0 else {
            let code = errno
            try? fileManager.removeItem(at: temporaryURL)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: url.path])
        }
    }

    static func decode(_ data: Data) throws -> (String, String.Encoding) {
        if data.isEmpty { return ("", .utf8) }
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data.dropFirst(3), encoding: .utf8) {
            return (text, .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return (text, .utf16)
        }
        if looksBinary(data) { throw TextFileError.notText }
        if let text = String(data: data, encoding: .utf8) { return (text, .utf8) }
        if let text = String(data: data, encoding: .isoLatin1) { return (text, .isoLatin1) }
        throw TextFileError.undecodable
    }

    /// A NUL byte in the first 8 KB is a strong hint that this is not text.
    private static func looksBinary(_ data: Data) -> Bool {
        data.prefix(8192).contains(0)
    }
}
