import Foundation

/// A plain, sendable description of a directory child, produced off the main actor.
struct DirectoryEntry: Sendable {
    let url: URL
    let isDirectory: Bool
}
