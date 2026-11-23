import Foundation

public enum KeyFormat: String, Codable, CaseIterable, Sendable {
    case hex
    case base64
    case base64url
    case uuid
}

public struct KeyOptions: Codable, Hashable, Sendable {
    public static let byteRange = 8...128

    public var bytes: Int
    public var format: KeyFormat

    public init(bytes: Int = 32, format: KeyFormat = .base64url) {
        self.bytes = bytes
        self.format = format
    }
}

enum Key {
    static func generate<R: RandomSource>(_ options: KeyOptions, using rng: inout R) throws -> String {
        if options.format == .uuid {
            var b = rng.bytes(16)
            b[6] = (b[6] & 0x0F) | 0x40 // version 4
            b[8] = (b[8] & 0x3F) | 0x80 // RFC 4122 variant
            let hex = b.map { String(format: "%02x", $0) }.joined()
            let i = hex.startIndex
            func slice(_ from: Int, _ to: Int) -> Substring {
                hex[hex.index(i, offsetBy: from)..<hex.index(i, offsetBy: to)]
            }
            return [slice(0, 8), slice(8, 12), slice(12, 16), slice(16, 20), slice(20, 32)].joined(separator: "-")
        }
        guard KeyOptions.byteRange.contains(options.bytes) else {
            throw GeneratorError.lengthOutOfRange(KeyOptions.byteRange)
        }
        let data = Data(rng.bytes(options.bytes))
        switch options.format {
        case .hex:
            return data.map { String(format: "%02x", $0) }.joined()
        case .base64:
            return data.base64EncodedString()
        case .base64url:
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        case .uuid:
            fatalError("handled above")
        }
    }

    static func entropy(_ options: KeyOptions) -> Double {
        options.format == .uuid ? 122 : Double(options.bytes * 8)
    }
}
