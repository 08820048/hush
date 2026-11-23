import Foundation

/// A parsed Apple "password rules" string, the format used by the `passwordrules` HTML
/// attribute and by Apple's password-manager-resources:
///
///     minlength: 8; maxlength: 16; required: lower, upper; required: digit; allowed: [-!#$];
///
/// - `required:` each statement is a group; the password needs at least one character from it.
/// - `allowed:` characters that may appear in addition to the required ones.
/// - `max-consecutive:` the longest run of one repeated character.
/// - Classes: `upper`, `lower`, `digit`, `special`, `ascii-printable`, `unicode` and custom
///   sets in brackets. In a custom set `-` may only come first and `]` only last (`[-!]]`).
///
/// Parsing is lenient like Apple's: unknown properties and malformed parts are skipped.
public struct PasswordRules: Equatable, Sendable {
    public var minLength: Int?
    public var maxLength: Int?
    public var maxConsecutive: Int?
    /// One entry per `required:` statement.
    public var required: [Set<Character>] = []
    /// Union of all `allowed:` statements.
    public var allowed: Set<Character> = []

    public init(minLength: Int? = nil, maxLength: Int? = nil, maxConsecutive: Int? = nil,
                required: [Set<Character>] = [], allowed: Set<Character> = []) {
        self.minLength = minLength
        self.maxLength = maxLength
        self.maxConsecutive = maxConsecutive
        self.required = required
        self.allowed = allowed
    }

    // MARK: Character classes

    public enum Classes {
        public static let upper = Set(CharacterPools.uppercase)
        public static let lower = Set(CharacterPools.lowercase)
        public static let digit = Set(CharacterPools.digits)
        /// Apple's `special`: ASCII punctuation it accepts, without space, `/` and `\`.
        public static let special = Set("-~!@#$%^&*_+=`|(){}[:;\"'<>,.?]")
        /// Printable ASCII without space (Hush never generates spaces).
        public static let asciiPrintable = upper.union(lower).union(digit).union(CharacterPools.allSymbols)
    }

    // MARK: Parsing

    public init(parsing text: String) {
        let chars = Array(text)
        var i = 0

        func skipSpaces() { while i < chars.count, chars[i].isWhitespace { i += 1 } }

        while i < chars.count {
            skipSpaces()
            // Property name up to ':'
            var name = ""
            while i < chars.count, chars[i] != ":", chars[i] != ";" { name.append(chars[i]); i += 1 }
            guard i < chars.count, chars[i] == ":" else { i += 1; continue }
            i += 1
            name = name.trimmingCharacters(in: .whitespaces).lowercased()

            switch name {
            case "required", "allowed":
                var set = Set<Character>()
                while i < chars.count {
                    skipSpaces()
                    guard i < chars.count else { break }
                    if chars[i] == ";" { i += 1; break }
                    if chars[i] == "," { i += 1; continue }
                    if chars[i] == "[" {
                        set.formUnion(Self.parseCustomSet(chars, &i))
                    } else {
                        var identifier = ""
                        while i < chars.count, chars[i].isLetter || chars[i] == "-" { identifier.append(chars[i]); i += 1 }
                        if identifier.isEmpty { i += 1; continue } // stray character
                        set.formUnion(Self.named(identifier.lowercased()))
                    }
                }
                if name == "required" {
                    if !set.isEmpty { required.append(set) }
                } else {
                    allowed.formUnion(set)
                }
            default:
                var value = ""
                while i < chars.count, chars[i] != ";" { value.append(chars[i]); i += 1 }
                i += 1
                guard let number = Int(value.trimmingCharacters(in: .whitespaces)), number > 0 else { continue }
                switch name {
                case "minlength": minLength = max(minLength ?? 0, number)
                case "maxlength": maxLength = min(maxLength ?? .max, number)
                case "max-consecutive": maxConsecutive = min(maxConsecutive ?? .max, number)
                default: break
                }
            }
        }
    }

    private static func named(_ identifier: String) -> Set<Character> {
        switch identifier {
        case "upper": Classes.upper
        case "lower": Classes.lower
        case "digit": Classes.digit
        case "special": Classes.special
        case "ascii-printable", "unicode": Classes.asciiPrintable
        default: []
        }
    }

    /// Reads `[...]` starting at `i` (which points at `[`). A `]` immediately followed by
    /// another `]` is a member of the set; the second one closes it.
    private static func parseCustomSet(_ chars: [Character], _ i: inout Int) -> Set<Character> {
        i += 1
        var set = Set<Character>()
        while i < chars.count {
            let c = chars[i]
            if c == "]" {
                if i + 1 < chars.count, chars[i + 1] == "]" {
                    set.insert("]")
                    i += 2
                } else {
                    i += 1
                }
                break
            }
            if c.isASCII, !c.isWhitespace { set.insert(c) } // non-ASCII and spaces are not generated
            i += 1
        }
        return set
    }

    // MARK: Using the rules

    /// Every character the rules permit. No `required`/`allowed` at all means printable ASCII.
    public var permittedCharacters: Set<Character> {
        let union = required.reduce(allowed) { $0.union($1) }
        return union.isEmpty ? Classes.asciiPrintable : union
    }

    /// Random-mode options that always produce a compliant password, as close to
    /// `preferredLength` as the length limits allow.
    public func randomOptions(preferredLength: Int = RandomOptions().length) -> RandomOptions {
        let permitted = permittedCharacters
        let range = RandomOptions.lengthRange
        let lower = max(minLength ?? range.lowerBound, range.lowerBound, required.count)
        let upper = min(maxLength ?? range.upperBound, range.upperBound)
        let length = min(max(preferredLength, lower), max(upper, lower))

        let letterAndDigits = Classes.upper.union(Classes.lower).union(Classes.digit)
        let symbols = CharacterPools.allSymbols.filter { permitted.contains($0) }
        let excluded = String(CharacterPools.uppercase + CharacterPools.lowercase + CharacterPools.digits)
            .filter { letterAndDigits.contains($0) && !permitted.contains($0) }

        return RandomOptions(
            length: length,
            uppercase: !permitted.isDisjoint(with: Classes.upper),
            lowercase: !permitted.isDisjoint(with: Classes.lower),
            digits: !permitted.isDisjoint(with: Classes.digit),
            symbols: !symbols.isEmpty,
            symbolSet: symbols.isEmpty ? CharacterPools.allSymbols : symbols,
            excludeAmbiguous: false,
            excludedCharacters: excluded,
            // Every permitted class appears: stronger than most rules ask, never weaker.
            requireEachClass: true,
            // Required groups that are narrower than a whole class (e.g. "one of !#$").
            requiredGroups: required.map { group in String(CharacterPools.allSymbols.filter(group.contains) + String(letterAndDigits.filter(group.contains)).sorted()) },
            maxConsecutive: maxConsecutive
        )
    }

    /// Whether `password` satisfies these rules.
    public func accepts(_ password: String) -> Bool {
        let chars = Array(password)
        if let minLength, chars.count < minLength { return false }
        if let maxLength, chars.count > maxLength { return false }
        if let maxConsecutive, RandomPassword.longestRun(chars) > maxConsecutive { return false }
        let permitted = permittedCharacters
        guard chars.allSatisfy(permitted.contains) else { return false }
        let present = Set(chars)
        return required.allSatisfy { !$0.isDisjoint(with: present) }
    }
}
