import AppKit

/// Finder's own icons, cached by file extension so the tree scrolls smoothly.
@MainActor
enum FileIconProvider {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        let key = url.hasDirectoryPath ? "/folder" : url.pathExtension.lowercased()
        if let cached = cache[key] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 16, height: 16)
        cache[key] = image
        return image
    }
}
