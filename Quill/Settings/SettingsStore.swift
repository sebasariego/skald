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

    static let key = "dev.local.quill.settings"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Snapshot {
        guard let data = defaults.data(forKey: Self.key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return .default
        }
        return snapshot
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
