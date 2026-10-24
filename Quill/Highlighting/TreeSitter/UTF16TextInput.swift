import Foundation
import TreeSitter

/// Feeds an `NSString` to tree-sitter as UTF-16LE in fixed-size chunks. Byte offsets
/// are UTF-16 offsets times two, which keeps every conversion in the adapter trivial.
final class UTF16TextInput {
    private let string: NSString
    private let capacity = 4096
    private let buffer: UnsafeMutablePointer<UInt16>

    init(_ text: TextSnapshot) {
        string = text.string
        buffer = UnsafeMutablePointer<UInt16>.allocate(capacity: capacity)
    }

    deinit {
        buffer.deallocate()
    }

    /// Runs `body` with a `TSInput` that stays valid for the duration of the call.
    func withInput<T>(_ body: (TSInput) -> T) -> T {
        let unmanaged = Unmanaged.passUnretained(self)
        let input = TSInput(
            payload: unmanaged.toOpaque(),
            read: { payload, byteIndex, _, bytesRead in
                guard let payload else {
                    bytesRead?.pointee = 0
                    return nil
                }
                return Unmanaged<UTF16TextInput>.fromOpaque(payload).takeUnretainedValue().read(byteIndex: byteIndex, bytesRead: bytesRead)
            },
            encoding: TSInputEncodingUTF16LE,
            decode: nil
        )
        return withExtendedLifetime(self) { body(input) }
    }

    private func read(byteIndex: UInt32, bytesRead: UnsafeMutablePointer<UInt32>?) -> UnsafePointer<CChar>? {
        let offset = Int(byteIndex / 2)
        let length = string.length
        guard offset < length else {
            bytesRead?.pointee = 0
            return nil
        }
        let count = min(capacity, length - offset)
        string.getCharacters(buffer, range: NSRange(location: offset, length: count))
        bytesRead?.pointee = UInt32(count * 2)
        return UnsafeRawPointer(buffer).assumingMemoryBound(to: CChar.self)
    }
}
