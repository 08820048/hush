import Foundation

/// Consonant–vowel syllables that are easy to say and to hear: "Tobavu-Kimeso-42".
public struct PronounceableOptions: Codable, Hashable, Sendable {
    public static let groupRange = 2...6

    public var groups: Int
    public var syllablesPerGroup: Int
    public var separator: String
    public var digits: Int

    public init(groups: Int = 3, syllablesPerGroup: Int = 3, separator: String = "-", digits: Int = 2) {
        self.groups = groups
        self.syllablesPerGroup = syllablesPerGroup
        self.separator = separator
        self.digits = digits
    }
}

enum Pronounceable {
    /// No c/q/w/x/y: they are the letters people mishear or spell differently.
    static let consonants = Array("bdfghjklmnprstvz")
    static let vowels = Array("aeiou")

    static func generate<R: RandomSource>(_ options: PronounceableOptions, using rng: inout R) throws -> String {
        guard PronounceableOptions.groupRange.contains(options.groups), (1...4).contains(options.syllablesPerGroup) else {
            throw GeneratorError.lengthOutOfRange(PronounceableOptions.groupRange)
        }
        var parts: [String] = (0..<options.groups).map { _ in
            var group = ""
            for _ in 0..<options.syllablesPerGroup {
                group.append(rng.pick(consonants))
                group.append(rng.pick(vowels))
            }
            // Capitalising a fixed position adds no entropy and is counted as none.
            return group.prefix(1).uppercased() + group.dropFirst()
        }
        if options.digits > 0 {
            parts.append(String((0..<options.digits).map { _ in Character(String(rng.uniform(10))) }))
        }
        return parts.joined(separator: options.separator)
    }

    static func entropy(_ options: PronounceableOptions) -> Double {
        let perSyllable = log2(Double(consonants.count * vowels.count))
        return Double(options.groups * options.syllablesPerGroup) * perSyllable + Double(options.digits) * log2(10)
    }
}
