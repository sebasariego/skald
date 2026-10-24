import Foundation

/// Persists `SessionState` in user defaults using security-scoped bookmarks, which is
/// the only way a sandboxed app can reopen files without asking again.
struct SessionStore {
    static let key = "dev.local.skald.session"
    /// Key used while the app was called Quill. Its security-scoped bookmarks were issued to
    /// the old bundle identifier and will not resolve, so this only matters for tests and
    /// unsandboxed runs; it is read for completeness.
    static let legacyKey = "dev.local.quill.session"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SessionState? {
        guard let data = defaults.data(forKey: Self.key) ?? defaults.data(forKey: Self.legacyKey) else { return nil }
        return try? JSONDecoder().decode(SessionState.self, from: data)
    }

    func save(_ state: SessionState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    /// Security-scoped when the process is sandboxed; a plain bookmark otherwise (tests).
    static func bookmark(for url: URL) -> Data? {
        if let scoped = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            return scoped
        }
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves a bookmark and starts security-scoped access, which stays open for the
    /// life of the process. Returns nil when the file is gone.
    static func resolve(_ bookmark: Data) -> URL? {
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            _ = url.startAccessingSecurityScopedResource()
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return nil
    }
}
