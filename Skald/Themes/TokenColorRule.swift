import Foundation

/// One `tokenColors` entry: TextMate scopes and the style they get.
struct TokenColorRule: Equatable {
    var scopes: [String]
    var style: TokenStyle
}
