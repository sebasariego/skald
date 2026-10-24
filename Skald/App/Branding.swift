import Foundation

/// The application's identity. Skald: an Old Norse poet. The Ansuz rune (\u{16A8}) stands for
/// language, wisdom and inspiration and serves as the app's symbolic mark.
enum Branding {
    static let appName = "Skald"
    static let rune = "\u{16A8}"
    static let tagline = "A native macOS code editor."
    /// The bundle identifier the app shipped under before the rename, for migrating preferences.
    static let legacyBundleIdentifier = "dev.local.quill"
}
