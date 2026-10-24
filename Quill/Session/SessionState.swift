import Foundation

/// What gets restored at launch: the folder, the open files and which one was showing.
struct SessionState: Codable, Equatable {
    var folderBookmark: Data?
    var fileBookmarks: [Data] = []
    var selectedIndex: Int?
}
