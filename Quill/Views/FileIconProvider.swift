import Foundation

/// SF Symbol names for sidebar rows: thin monochrome glyphs instead of Finder's
/// colored document icons, grouped by what the file is rather than its exact type.
enum FileIconProvider {
    static let folderSymbol = "folder"
    static let openFolderSymbol = "folder"

    static func symbolName(for url: URL, isDirectory: Bool) -> String {
        if isDirectory { return folderSymbol }
        return symbolName(forExtension: url.pathExtension, fileName: url.lastPathComponent)
    }

    static func symbolName(forExtension ext: String, fileName: String = "") -> String {
        let name = fileName.lowercased()
        if name.hasPrefix(".") || name == "makefile" || name == "dockerfile" { return "gearshape" }
        switch ext.lowercased() {
        case "swift", "py", "pyi", "js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx", "rb", "go", "rs", "c", "cc", "cpp", "h", "hpp", "m", "mm", "java", "kt", "kts", "scala", "php", "lua", "pl", "r", "cs", "dart", "ex", "exs", "hs", "elm", "clj", "sql":
            return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash", "zsh", "fish", "command", "bat", "ps1":
            return "terminal"
        case "html", "htm", "xhtml", "vue", "svelte":
            return "globe"
        case "css", "scss", "sass", "less":
            return "paintbrush"
        case "json", "jsonc", "yaml", "yml", "toml", "ini", "cfg", "conf", "plist", "env", "lock":
            return "curlybraces"
        case "xml", "xsl", "xslt", "xib", "storyboard", "xcscheme", "entitlements":
            return "chevron.left.forwardslash.chevron.right"
        case "md", "markdown", "txt", "rtf", "text", "rst", "adoc", "log":
            return "doc.text"
        case "pdf":
            return "doc.richtext"
        case "doc", "docx", "pages", "odt":
            return "doc"
        case "xls", "xlsx", "numbers", "csv", "tsv", "ods":
            return "tablecells"
        case "ppt", "pptx", "key", "odp":
            return "rectangle.on.rectangle"
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp", "ico", "icns":
            return "photo"
        case "svg", "ai", "sketch", "fig", "eps":
            return "pencil.and.outline"
        case "mp3", "wav", "aac", "flac", "m4a", "ogg":
            return "waveform"
        case "mp4", "mov", "m4v", "avi", "mkv", "webm":
            return "film"
        case "zip", "tar", "gz", "bz2", "xz", "7z", "rar", "dmg":
            return "archivebox"
        case "ttf", "otf", "woff", "woff2":
            return "textformat"
        case "app", "pkg", "ipa", "apk":
            return "shippingbox"
        case "xcodeproj", "xcworkspace":
            return "hammer"
        default:
            return "doc"
        }
    }
}
