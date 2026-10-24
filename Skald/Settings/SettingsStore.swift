import Foundation

/// Persists editor settings as one JSON blob in user defaults. Reads happen once at
/// launch; writes happen on every change, which is rare and cheap.
struct SettingsStore {
    struct Snapshot: Codable, Equatable {
        var editor: EditorConfiguration
        var themeName: String?
        /// Bundle identifier of the preferred terminal app; nil or "automatic" picks the first installed.
        var terminalID: String?

        static let `default` = Snapshot(editor: EditorConfiguration(), themeName: nil, terminalID: nil)
    }

    static let key = "dev.local.skald.settings"
    /// Key used while the app was called Quill; read when the new key is empty.
    static let legacyKey = "dev.local.quill.settings"
    let defaults: UserDefaults
    /// Where the Quill-era defaults live when they are reachable (unsandboxed runs, tests, or
    /// after `Scripts/migrate-from-quill.sh` copied them next to ours).
    let legacyDefaults: UserDefaults?

    init(defaults: UserDefaults = .standard, legacyDefaults: UserDefaults? = UserDefaults(suiteName: Branding.legacyBundleIdentifier)) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
    }

    func load() -> Snapshot {
        if let snapshot = decode(defaults.data(forKey: Self.key)) { return snapshot }
        // First launch after the rename: adopt whatever Quill had saved.
        let candidates = [defaults.data(forKey: Self.legacyKey), legacyDefaults?.data(forKey: Self.legacyKey)]
        for data in candidates {
            if let snapshot = decode(data) {
                save(snapshot)
                return snapshot
            }
        }
        return .default
    }

    private func decode(_ data: Data?) -> Snapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
