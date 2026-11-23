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
    /// Extra groups the password must hit: at least one character from each group
    /// (website rules such as "at least one of !#$"). Characters outside the alphabet are ignored.
    public var requiredGroups: [String]
    /// The same character never appears more than this many times in a row. `nil` = no limit.
    public var maxConsecutive: Int?

    public init(
        length: Int = 20,
        uppercase: Bool = true,
        lowercase: Bool = true,
        digits: Bool = true,
        symbols: Bool = true,
        symbolSet: String = CharacterPools.allSymbols,
        excludeAmbiguous: Bool = false,
        excludedCharacters: String = "",
        requireEachClass: Bool = true,
        requiredGroups: [String] = [],
        maxConsecutive: Int? = nil
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
        self.requiredGroups = requiredGroups
        self.maxConsecutive = maxConsecutive
    }

    /// Decodes settings saved by older versions, which lack the newer fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = RandomOptions()
        length = try c.decodeIfPresent(Int.self, forKey: .length) ?? defaults.length
        uppercase = try c.decodeIfPresent(Bool.self, forKey: .uppercase) ?? defaults.uppercase
        lowercase = try c.decodeIfPresent(Bool.self, forKey: .lowercase) ?? defaults.lowercase
        digits = try c.decodeIfPresent(Bool.self, forKey: .digits) ?? defaults.digits
        symbols = try c.decodeIfPresent(Bool.self, forKey: .symbols) ?? defaults.symbols
        symbolSet = try c.decodeIfPresent(String.self, forKey: .symbolSet) ?? defaults.symbolSet
        excludeAmbiguous = try c.decodeIfPresent(Bool.self, forKey: .excludeAmbiguous) ?? defaults.excludeAmbiguous
        excludedCharacters = try c.decodeIfPresent(String.self, forKey: .excludedCharacters) ?? defaults.excludedCharacters
        requireEachClass = try c.decodeIfPresent(Bool.self, forKey: .requireEachClass) ?? defaults.requireEachClass
        requiredGroups = try c.decodeIfPresent([String].self, forKey: .requiredGroups) ?? []
        maxConsecutive = try c.decodeIfPresent(Int.self, forKey: .maxConsecutive)
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

/// The full set of constraints a candidate must satisfy, derived once from the options.
struct RandomConstraints {
    let alphabet: [Character]
    /// Each set must contribute at least one character.
    let mustHit: [Set<Character>]
    let maxConsecutive: Int?

    init(_ options: RandomOptions) throws {
        let pools = options.pools()
        guard !pools.isEmpty else { throw GeneratorError.emptyCharacterSet }
        alphabet = pools.flatMap { $0 }
        let inAlphabet = Set(alphabet)

        var sets: [Set<Character>] = []
        if options.requireEachClass, options.length >= pools.count, pools.count > 1 {
            sets = pools.map(Set.init)
        }
        for group in options.requiredGroups {
            let usable = Set(group).intersection(inAlphabet)
            // A required group with nothing generable can never be satisfied.
            guard !usable.isEmpty else { throw GeneratorError.emptyCharacterSet }
            // A group that already contains a whole required set adds nothing.
            if !sets.contains(where: { $0.isSubset(of: usable) }) { sets.append(usable) }
        }
        mustHit = sets
        maxConsecutive = options.maxConsecutive.map { max($0, 1) }
    }

    func accepts(_ characters: [Character]) -> Bool {
        if let limit = maxConsecutive, RandomPassword.longestRun(characters) > limit { return false }
        let present = Set(characters)
        return mustHit.allSatisfy { !$0.isDisjoint(with: present) }
    }
}

enum RandomPassword {
    static func generate<R: RandomSource>(_ options: RandomOptions, using rng: inout R) throws -> String {
        let constraints = try RandomConstraints(options)
        guard RandomOptions.lengthRange.contains(options.length) else {
            throw GeneratorError.lengthOutOfRange(RandomOptions.lengthRange)
        }
        guard constraints.mustHit.count <= options.length else { throw GeneratorError.lengthOutOfRange(constraints.mustHit.count...RandomOptions.lengthRange.upperBound) }

        // Draw whole strings uniformly and reject the ones that break a rule. Forcing a
        // character into a fixed position would make some strings likelier than others.
        while true {
            let candidate = (0..<options.length).map { _ in rng.pick(constraints.alphabet) }
            if constraints.accepts(candidate) {
                return String(candidate)
            }
        }
    }

    /// Replaces the character at `index` with a fresh random one, keeping every rule.
    static func reroll<R: RandomSource>(_ password: String, at index: Int, options: RandomOptions, using rng: inout R) throws -> String {
        var characters = Array(password)
        guard characters.indices.contains(index) else { return password }
        let constraints = try RandomConstraints(options)
        let original = characters[index]
        for _ in 0..<1_000 {
            let replacement = rng.pick(constraints.alphabet)
            if replacement == original && constraints.alphabet.count > 1 { continue }
            characters[index] = replacement
            if constraints.accepts(characters) { return String(characters) }
        }
        return password
    }

    static func covers(_ characters: [Character], _ pools: [[Character]]) -> Bool {
        let present = Set(characters)
        return pools.allSatisfy { pool in pool.contains(where: present.contains) }
    }

    static func longestRun(_ characters: [Character]) -> Int {
        var longest = 0, run = 0
        var previous: Character?
        for c in characters {
            run = c == previous ? run + 1 : 1
            longest = max(longest, run)
            previous = c
        }
        return longest
    }

    /// Exact entropy in bits: log2 of the number of strings the generator can return.
    ///
    /// Counting uses inclusion–exclusion over the must-hit sets: the strings that avoid every
    /// set in S are exactly the strings over the alphabet minus their union. Each term is the
    /// number of strings over k symbols with no run longer than the limit, kept as a fraction
    /// of n^length so the large numbers never overflow.
    static func entropy(_ options: RandomOptions) -> Double {
        guard let constraints = try? RandomConstraints(options) else { return 0 }
        let n = constraints.alphabet.count
        let length = options.length
        let sets = constraints.mustHit
        guard sets.count <= 16 else { return Double(length) * log2(Double(n)) }

        var fraction = 0.0
        for mask in 0..<(1 << sets.count) {
            var avoided = Set<Character>()
            var bits = 0
            for (i, set) in sets.enumerated() where mask & (1 << i) != 0 {
                avoided.formUnion(set)
                bits += 1
            }
            let term = fractionOfStrings(alphabet: n - avoided.count, of: n, length: length, maxRun: constraints.maxConsecutive)
            fraction += bits.isMultiple(of: 2) ? term : -term
        }
        return Double(length) * log2(Double(n)) + log2(max(fraction, .leastNonzeroMagnitude))
    }

    /// (number of strings of `length` over `k` symbols with no run longer than `maxRun`) / n^length.
    static func fractionOfStrings(alphabet k: Int, of n: Int, length: Int, maxRun: Int?) -> Double {
        guard k > 0, length > 0 else { return k > 0 || length == 0 ? 1 : 0 }
        let ratio = Double(k) / Double(n)
        guard let limit = maxRun, limit < length else { return pow(ratio, Double(length)) }

        // endingRun[j]: strings whose last j+1 characters are equal (and no longer run), scaled.
        var endingRun = [Double](repeating: 0, count: limit)
        endingRun[0] = ratio
        for _ in 1..<length {
            let total = endingRun.reduce(0, +)
            var next = [Double](repeating: 0, count: limit)
            next[0] = total * Double(k - 1) / Double(n)
            for j in 1..<limit { next[j] = endingRun[j - 1] / Double(n) }
            endingRun = next
        }
        return endingRun.reduce(0, +)
    }
}
