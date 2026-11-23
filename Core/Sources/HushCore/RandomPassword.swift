import Foundation

/// Character pools used by the random mode.
public enum CharacterPools {
    public static let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    public static let lowercase = "abcdefghijklmnopqrstuvwxyz"
    public static let digits = "0123456789"
    /// All 32 printable ASCII punctuation characters.
    public static let allSymbols = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    /// A conservative set most sites accept.
    public static let compatibleSymbols = "!@#$%"
    /// Characters that are easy to confuse when read or typed.
    public static let ambiguous: Set<Character> = ["0", "O", "o", "1", "l", "I", "|", "`", "'", "\""]
}

public enum CharacterKind: Sendable, Equatable {
    case letter, digit, symbol

    public init(_ character: Character) {
        if character.isASCII, character.isLetter { self = .letter }
        else if character.isASCII, character.isNumber { self = .digit }
        else { self = .symbol }
    }
}

public struct RandomOptions: Codable, Hashable, Sendable {
    public static let lengthRange = 4...128

    public var length: Int
    public var uppercase: Bool
    public var lowercase: Bool
    public var digits: Bool
    public var symbols: Bool
    public var symbolSet: String
    public var excludeAmbiguous: Bool
    /// Extra characters the user never wants to see.
    public var excludedCharacters: String
    /// Every enabled class appears at least once.
    public var requireEachClass: Bool

    public init(
        length: Int = 20,
        uppercase: Bool = true,
        lowercase: Bool = true,
        digits: Bool = true,
        symbols: Bool = true,
        symbolSet: String = CharacterPools.allSymbols,
        excludeAmbiguous: Bool = false,
        excludedCharacters: String = "",
        requireEachClass: Bool = true
    ) {
        self.length = length
        self.uppercase = uppercase
        self.lowercase = lowercase
        self.digits = digits
        self.symbols = symbols
        self.symbolSet = symbolSet
        self.excludeAmbiguous = excludeAmbiguous
        self.excludedCharacters = excludedCharacters
        self.requireEachClass = requireEachClass
    }

    /// The enabled, non-empty, mutually disjoint character pools after exclusions.
    public func pools() -> [[Character]] {
        var excluded = Set(excludedCharacters)
        if excludeAmbiguous { excluded.formUnion(CharacterPools.ambiguous) }

        // Symbols never contain letters or digits, so the pools stay disjoint.
        let symbolCharacters = symbolSet.filter { $0.isASCII && !$0.isLetter && !$0.isNumber && !$0.isWhitespace }

        var result: [[Character]] = []
        for (enabled, source) in [
            (uppercase, CharacterPools.uppercase),
            (lowercase, CharacterPools.lowercase),
            (digits, CharacterPools.digits),
            (symbols, symbolCharacters),
        ] where enabled {
            var seen = Set<Character>()
            let pool = source.filter { !excluded.contains($0) && seen.insert($0).inserted }
            if !pool.isEmpty { result.append(Array(pool)) }
        }
        return result
    }
}

enum RandomPassword {
    static func generate<R: RandomSource>(_ options: RandomOptions, using rng: inout R) throws -> String {
        let pools = options.pools()
        guard !pools.isEmpty else { throw GeneratorError.emptyCharacterSet }
        guard RandomOptions.lengthRange.contains(options.length) else {
            throw GeneratorError.lengthOutOfRange(RandomOptions.lengthRange)
        }
        let alphabet = pools.flatMap { $0 }
        let mustCoverAll = options.requireEachClass && options.length >= pools.count

        // Draw whole strings uniformly and reject the ones that miss a class. Forcing a
        // character into a fixed position would make some strings likelier than others.
        while true {
            let candidate = (0..<options.length).map { _ in rng.pick(alphabet) }
            if !mustCoverAll || covers(candidate, pools) {
                return String(candidate)
            }
        }
    }

    /// Replaces the character at `index` with a fresh random one, keeping the
    /// "every class at least once" rule if it was on.
    static func reroll<R: RandomSource>(_ password: String, at index: Int, options: RandomOptions, using rng: inout R) throws -> String {
        var characters = Array(password)
        guard characters.indices.contains(index) else { return password }
        let pools = options.pools()
        guard !pools.isEmpty else { throw GeneratorError.emptyCharacterSet }
        let alphabet = pools.flatMap { $0 }
        let mustCoverAll = options.requireEachClass && characters.count >= pools.count
        let original = characters[index]
        for _ in 0..<1_000 {
            let replacement = rng.pick(alphabet)
            if replacement == original && alphabet.count > 1 { continue }
            characters[index] = replacement
            if !mustCoverAll || covers(characters, pools) { return String(characters) }
        }
        return password
    }

    static func covers(_ characters: [Character], _ pools: [[Character]]) -> Bool {
        let present = Set(characters)
        return pools.allSatisfy { pool in pool.contains(where: present.contains) }
    }

    /// Exact entropy in bits, including the reduction from the "each class" rule
    /// (inclusion–exclusion over the pools).
    static func entropy(_ options: RandomOptions) -> Double {
        let pools = options.pools()
        guard !pools.isEmpty else { return 0 }
        let n = Double(pools.reduce(0) { $0 + $1.count })
        let length = options.length
        let full = Double(length) * log2(n)
        guard options.requireEachClass, length >= pools.count, pools.count > 1 else { return full }

        // Fraction of all strings that contain every pool:
        // sum over subsets S of (-1)^|S| * ((n - |S's chars|) / n)^length
        var fraction = 0.0
        for mask in 0..<(1 << pools.count) {
            var removed = 0
            var bits = 0
            for (i, pool) in pools.enumerated() where mask & (1 << i) != 0 {
                removed += pool.count
                bits += 1
            }
            let term = pow((n - Double(removed)) / n, Double(length))
            fraction += bits.isMultiple(of: 2) ? term : -term
        }
        return full + log2(max(fraction, .leastNonzeroMagnitude))
    }
}
