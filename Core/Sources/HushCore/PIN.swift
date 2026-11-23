import Foundation

public struct PINOptions: Codable, Hashable, Sendable {
    public static let lengthRange = 4...12

    public var length: Int
    /// Rejects repeats, runs, mirrored pairs and date-like PINs.
    public var avoidWeakPatterns: Bool

    public init(length: Int = 6, avoidWeakPatterns: Bool = true) {
        self.length = length
        self.avoidWeakPatterns = avoidWeakPatterns
    }
}

enum PIN {
    static func generate<R: RandomSource>(_ options: PINOptions, using rng: inout R) throws -> String {
        guard PINOptions.lengthRange.contains(options.length) else {
            throw GeneratorError.lengthOutOfRange(PINOptions.lengthRange)
        }
        while true {
            let pin = String((0..<options.length).map { _ in Character(String(rng.uniform(10))) })
            if !options.avoidWeakPatterns || !isWeak(pin) { return pin }
        }
    }

    static func entropy(_ options: PINOptions) -> Double {
        let total = pow(10, Double(options.length))
        guard options.avoidWeakPatterns else { return log2(total) }
        return log2(total - Double(WeakPINs.count(length: options.length)))
    }

    static func isWeak(_ pin: String) -> Bool {
        WeakPINs.isWeak(pin)
    }
}

/// The exact set of PINs Hush refuses to produce, so the reported entropy is honest.
enum WeakPINs {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Int: Set<String>] = [:]

    static func isWeak(_ pin: String) -> Bool {
        set(length: pin.count).contains(pin)
    }

    static func count(length: Int) -> Int {
        set(length: length).count
    }

    static func set(length: Int) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[length] { return cached }
        let built = build(length: length)
        cache[length] = built
        return built
    }

    private static func build(length: Int) -> Set<String> {
        var weak = Set<String>()

        // Short patterns repeated at least twice: 000000, 121212, 123123, 12341234.
        for period in 1...min(4, length / 2) {
            let combinations = Int(pow(10, Double(period)))
            for value in 0..<combinations {
                let unit = String(format: "%0\(period)d", value)
                let repeated = String(String(repeating: unit, count: length / period + 1).prefix(length))
                weak.insert(repeated)
            }
        }

        // Straight runs up or down: 123456, 987654, 345678.
        for start in 0...9 {
            for step in [1, -1] {
                var digits = ""
                var d = start
                for _ in 0..<length {
                    digits += String((d % 10 + 10) % 10)
                    d += step
                }
                weak.insert(digits)
            }
        }

        // Doubled digits: 112233, 99887766.
        if length.isMultiple(of: 2), length <= 8 {
            let half = length / 2
            for value in 0..<Int(pow(10, Double(half))) {
                let unit = String(format: "%0\(half)d", value)
                weak.insert(String(unit.flatMap { [$0, $0] }))
            }
        }

        // Dates and years.
        func two(_ n: Int) -> String { String(format: "%02d", n) }
        func four(_ n: Int) -> String { String(format: "%04d", n) }
        let years = 1900...2099
        switch length {
        case 4:
            for m in 1...12 { for d in 1...31 { weak.insert(two(m) + two(d)); weak.insert(two(d) + two(m)) } }
            for y in years { weak.insert(four(y)) }
        case 6:
            for y in 0...99 { for m in 1...12 { for d in 1...31 {
                weak.insert(two(y) + two(m) + two(d))
                weak.insert(two(d) + two(m) + two(y))
                weak.insert(two(m) + two(d) + two(y))
            } } }
        case 8:
            for y in years { for m in 1...12 { for d in 1...31 {
                weak.insert(four(y) + two(m) + two(d))
                weak.insert(two(d) + two(m) + four(y))
                weak.insert(two(m) + two(d) + four(y))
            } } }
        default:
            break
        }
        return weak
    }
}
