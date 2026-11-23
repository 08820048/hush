import Foundation

public struct PassphraseOptions: Codable, Hashable, Sendable {
    public static let wordCountRange = 3...10
    public static let separators = ["-", ".", "_", " "]

    public var wordCount: Int
    public var separator: String
    public var capitalize: Bool
    /// Appends one random digit to the last word (adds log2(10) bits).
    public var appendDigit: Bool

    public init(wordCount: Int = 5, separator: String = "-", capitalize: Bool = true, appendDigit: Bool = true) {
        self.wordCount = wordCount
        self.separator = separator
        self.capitalize = capitalize
        self.appendDigit = appendDigit
    }
}

enum Passphrase {
    static var wordlist: [String] { EFFWordlist.words }

    static func generate<R: RandomSource>(_ options: PassphraseOptions, using rng: inout R) throws -> String {
        guard PassphraseOptions.wordCountRange.contains(options.wordCount) else {
            throw GeneratorError.lengthOutOfRange(PassphraseOptions.wordCountRange)
        }
        let list = wordlist
        var words = (0..<options.wordCount).map { _ in rng.pick(list) }
        if options.capitalize {
            words = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        }
        if options.appendDigit {
            words[words.count - 1] += String(rng.uniform(10))
        }
        return words.joined(separator: options.separator)
    }

    static func entropy(_ options: PassphraseOptions) -> Double {
        Double(options.wordCount) * log2(Double(wordlist.count)) + (options.appendDigit ? log2(10) : 0)
    }
}
