import Foundation

public enum GeneratorError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyCharacterSet
    case lengthOutOfRange(ClosedRange<Int>)

    public var description: String {
        switch self {
        case .emptyCharacterSet:
            return "No characters left to choose from. Enable at least one character class."
        case .lengthOutOfRange(let range):
            return "Length must be between \(range.lowerBound) and \(range.upperBound)."
        }
    }
}

public enum Mode: String, Codable, CaseIterable, Sendable {
    case random, passphrase, pin, pronounceable, key
}

/// Everything needed to produce one secret.
public enum GeneratorConfig: Codable, Hashable, Sendable {
    case random(RandomOptions)
    case passphrase(PassphraseOptions)
    case pin(PINOptions)
    case pronounceable(PronounceableOptions)
    case key(KeyOptions)

    public var mode: Mode {
        switch self {
        case .random: .random
        case .passphrase: .passphrase
        case .pin: .pin
        case .pronounceable: .pronounceable
        case .key: .key
        }
    }

    public static func defaultConfig(for mode: Mode) -> GeneratorConfig {
        switch mode {
        case .random: .random(RandomOptions())
        case .passphrase: .passphrase(PassphraseOptions())
        case .pin: .pin(PINOptions())
        case .pronounceable: .pronounceable(PronounceableOptions())
        case .key: .key(KeyOptions())
        }
    }

    /// Entropy in bits of what this configuration produces.
    public var entropyBits: Double {
        switch self {
        case .random(let o): RandomPassword.entropy(o)
        case .passphrase(let o): Passphrase.entropy(o)
        case .pin(let o): PIN.entropy(o)
        case .pronounceable(let o): Pronounceable.entropy(o)
        case .key(let o): Key.entropy(o)
        }
    }
}

public struct Secret: Hashable, Sendable {
    public let value: String
    public let config: GeneratorConfig
    public let entropyBits: Double

    public var strength: Strength { Strength(bits: entropyBits) }
}

public enum Generator {
    public static func generate(_ config: GeneratorConfig) throws -> Secret {
        var rng = SecureRandom()
        return try generate(config, using: &rng)
    }

    public static func generate<R: RandomSource>(_ config: GeneratorConfig, using rng: inout R) throws -> Secret {
        let value: String
        switch config {
        case .random(let o): value = try RandomPassword.generate(o, using: &rng)
        case .passphrase(let o): value = try Passphrase.generate(o, using: &rng)
        case .pin(let o): value = try PIN.generate(o, using: &rng)
        case .pronounceable(let o): value = try Pronounceable.generate(o, using: &rng)
        case .key(let o): value = try Key.generate(o, using: &rng)
        }
        return Secret(value: value, config: config, entropyBits: config.entropyBits)
    }

    /// Re-rolls a single character of a random-mode password. Other modes are returned unchanged.
    public static func reroll(_ secret: Secret, at index: Int) throws -> Secret {
        var rng = SecureRandom()
        return try reroll(secret, at: index, using: &rng)
    }

    public static func reroll<R: RandomSource>(_ secret: Secret, at index: Int, using rng: inout R) throws -> Secret {
        guard case .random(let options) = secret.config else { return secret }
        let value = try RandomPassword.reroll(secret.value, at: index, options: options, using: &rng)
        return Secret(value: value, config: secret.config, entropyBits: secret.entropyBits)
    }
}

extension GeneratorConfig {
    /// The main size knob of each mode: characters (random), words (passphrase), digits (PIN),
    /// groups (pronounceable) or bytes (key). `nil` for UUID keys, which have a fixed size.
    public var primarySize: Int? {
        switch self {
        case .random(let o): o.length
        case .passphrase(let o): o.wordCount
        case .pin(let o): o.length
        case .pronounceable(let o): o.groups
        case .key(let o): o.format == .uuid ? nil : o.bytes
        }
    }

    /// Returns a copy with the main size set to `size`, or throws if it is out of range.
    public func withPrimarySize(_ size: Int) throws -> GeneratorConfig {
        func check(_ range: ClosedRange<Int>) throws {
            guard range.contains(size) else { throw GeneratorError.lengthOutOfRange(range) }
        }
        switch self {
        case .random(var o): try check(RandomOptions.lengthRange); o.length = size; return .random(o)
        case .passphrase(var o): try check(PassphraseOptions.wordCountRange); o.wordCount = size; return .passphrase(o)
        case .pin(var o): try check(PINOptions.lengthRange); o.length = size; return .pin(o)
        case .pronounceable(var o): try check(PronounceableOptions.groupRange); o.groups = size; return .pronounceable(o)
        case .key(var o):
            guard o.format != .uuid else { return self }
            try check(KeyOptions.byteRange); o.bytes = size; return .key(o)
        }
    }
}
