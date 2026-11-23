import Foundation
import Security

/// A source of uniformly distributed random integers.
///
/// Production code only ever uses ``SecureRandom``. The protocol exists so tests can
/// inject a deterministic source; HushCore itself ships no seedable generator.
public protocol RandomSource {
    /// Returns a uniformly distributed integer in `0..<upperBound`.
    mutating func uniform(_ upperBound: Int) -> Int
    /// Returns `count` uniformly distributed bytes.
    mutating func bytes(_ count: Int) -> [UInt8]
}

extension RandomSource {
    public mutating func bytes(_ count: Int) -> [UInt8] {
        (0..<count).map { _ in UInt8(uniform(256)) }
    }

    /// Picks a uniformly random element.
    public mutating func pick<C: RandomAccessCollection>(_ collection: C) -> C.Element where C.Index == Int {
        precondition(!collection.isEmpty, "cannot pick from an empty collection")
        return collection[collection.startIndex + uniform(collection.count)]
    }
}

/// The system CSPRNG (`SecRandomCopyBytes`), with rejection sampling so every value is
/// equally likely (no modulo bias).
public struct SecureRandom: RandomSource {
    public init() {}

    public mutating func uniform(_ upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be positive")
        let bound = UInt64(upperBound)
        // 2^64 mod bound: the number of values at the top of the range that would make
        // `v % bound` favour small results. Reject them and draw again.
        let remainder = (UInt64.max % bound &+ 1) % bound
        let acceptMax = UInt64.max - remainder
        while true {
            let value = Self.randomUInt64()
            if value <= acceptMax {
                return Int(value % bound)
            }
        }
    }

    public mutating func bytes(_ count: Int) -> [UInt8] {
        Self.secureBytes(count)
    }

    static func secureBytes(_ count: Int) -> [UInt8] {
        guard count > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: count)
        let status = buffer.withUnsafeMutableBytes { raw in
            SecRandomCopyBytes(kSecRandomDefault, count, raw.baseAddress!)
        }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        return buffer
    }

    static func randomUInt64() -> UInt64 {
        var value: UInt64 = 0
        let status = withUnsafeMutableBytes(of: &value) { raw in
            SecRandomCopyBytes(kSecRandomDefault, raw.count, raw.baseAddress!)
        }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        return value
    }
}
