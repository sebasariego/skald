import Foundation

/// A user-facing error ready for an alert.
struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
