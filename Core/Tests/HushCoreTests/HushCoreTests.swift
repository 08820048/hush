import Foundation
import Testing
@testable import HushCore

/// Deterministic generator for reproducible tests only. Never used by the app.
struct SplitMix64: RandomSource {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func uniform(_ upperBound: Int) -> Int { Int(next() % UInt64(upperBound)) }
}

// MARK: - Secure random

@Suite struct SecureRandomTests {
    @Test func staysInRange() {
        var rng = SecureRandom()
        for bound in [1, 2, 3, 10, 94, 7776, Int(UInt32.max)] {
            for _ in 0..<500 {
                let v = rng.uniform(bound)
                #expect(v >= 0 && v < bound)
            }
        }
    }

    /// Chi-square goodness of fit over 94 buckets. Critical value for df = 93 at p = 0.001 is ~136.
    @Test func uniformIsUnbiased() {
        var rng = SecureRandom()
        let buckets = 94, samples = 188_000
        var counts = [Int](repeating: 0, count: buckets)
        for _ in 0..<samples { counts[rng.uniform(buckets)] += 1 }
        let expected = Double(samples) / Double(buckets)
        let chi2 = counts.reduce(0.0) { $0 + pow(Double($1) - expected, 2) / expected }
        #expect(chi2 < 136, "chi-square \(chi2) suggests a biased distribution")
    }

    @Test func bytesHaveRequestedLength() {
        var rng = SecureRandom()
        #expect(rng.bytes(0).isEmpty)
        #expect(rng.bytes(32).count == 32)
        #expect(rng.bytes(32) != rng.bytes(32))
    }
}

// MARK: - Random mode

@Suite struct RandomPasswordTests {
    @Test func defaultPasswordMatchesOptions() throws {
        let options = RandomOptions()
        let allowed = Set(options.pools().flatMap { $0 })
        for _ in 0..<200 {
            let secret = try Generator.generate(.random(options))
            #expect(secret.value.count == 20)
            #expect(secret.value.allSatisfy(allowed.contains))
            #expect(secret.value.contains { $0.isUppercase })
            #expect(secret.value.contains { $0.isLowercase })
            #expect(secret.value.contains { $0.isNumber })
            #expect(secret.value.contains { CharacterPools.allSymbols.contains($0) })
        }
    }

    @Test func excludeAmbiguousRemovesConfusableCharacters() throws {
        let options = RandomOptions(length: 64, excludeAmbiguous: true)
        for _ in 0..<100 {
            let value = try Generator.generate(.random(options)).value
            #expect(!value.contains { CharacterPools.ambiguous.contains($0) })
        }
    }

    @Test func customExclusionsAndSymbols() throws {
        let options = RandomOptions(length: 40, symbolSet: "!@#", excludedCharacters: "abcXYZ9")
        for _ in 0..<100 {
            let value = try Generator.generate(.random(options)).value
            #expect(!value.contains { "abcXYZ9".contains($0) })
            #expect(!value.contains { CharacterKind($0) == .symbol && !"!@#".contains($0) })
        }
    }

    @Test func noClassesThrows() {
        let options = RandomOptions(uppercase: false, lowercase: false, digits: false, symbols: false)
        #expect(throws: GeneratorError.emptyCharacterSet) { try Generator.generate(.random(options)) }
    }

    @Test func lengthOutOfRangeThrows() {
        #expect(throws: GeneratorError.self) { try Generator.generate(.random(RandomOptions(length: 3))) }
        #expect(throws: GeneratorError.self) { try Generator.generate(.random(RandomOptions(length: 129))) }
    }

    @Test func entropyWithoutRuleIsLengthTimesLog2Alphabet() {
        let options = RandomOptions(length: 20, requireEachClass: false)
        #expect(abs(RandomPassword.entropy(options) - 20 * log2(94)) < 1e-9)
    }

    /// Inclusion–exclusion must match the closed-form count for two pools.
    @Test func entropyWithRuleIsExact() {
        let options = RandomOptions(length: 4, lowercase: false, symbols: false, requireEachClass: true)
        // 36⁴ strings, minus 26⁴ with no digit, minus 10⁴ with no letter.
        let valid = Double(1_679_616 - 456_976 - 10_000)
        #expect(abs(RandomPassword.entropy(options) - log2(valid)) < 1e-9)
    }

    @Test func defaultEntropyMatchesDesign() {
        // 20 characters from 94, minus a sliver for the "each class" rule: shown as 131 bits.
        let bits = GeneratorConfig.random(RandomOptions()).entropyBits
        #expect(bits > 130.5 && bits < 131.1)
    }

    /// Without the class rule every character is an independent uniform draw.
    @Test func characterDistributionIsUniform() throws {
        let options = RandomOptions(length: 50, requireEachClass: false)
        let alphabet = options.pools().flatMap { $0 }
        var counts = [Character: Int]()
        for _ in 0..<2_000 {
            for c in try Generator.generate(.random(options)).value { counts[c, default: 0] += 1 }
        }
        let total = Double(counts.values.reduce(0, +))
        let expected = total / Double(alphabet.count)
        let chi2 = alphabet.reduce(0.0) { $0 + pow(Double(counts[$1, default: 0]) - expected, 2) / expected }
        #expect(chi2 < 136, "chi-square \(chi2)")
    }

    @Test func rerollChangesOnlyOneCharacter() throws {
        var rng = SplitMix64(seed: 42)
        let secret = try Generator.generate(.random(RandomOptions()), using: &rng)
        let rerolled = try Generator.reroll(secret, at: 5, using: &rng)
        let a = Array(secret.value), b = Array(rerolled.value)
        #expect(a.count == b.count)
        #expect(a[5] != b[5])
        for i in a.indices where i != 5 { #expect(a[i] == b[i]) }
    }

    @Test func seededGenerationIsReproducible() throws {
        var a = SplitMix64(seed: 7), b = SplitMix64(seed: 7)
        #expect(try Generator.generate(.random(RandomOptions()), using: &a).value
            == Generator.generate(.random(RandomOptions()), using: &b).value)
    }
}

// MARK: - Other modes

@Suite struct OtherModeTests {
    @Test func passphraseShape() throws {
        let words = Set(EFFWordlist.words.map { $0.lowercased() })
        #expect(EFFWordlist.words.count == 7776)
        for _ in 0..<100 {
            let value = try Generator.generate(.passphrase(PassphraseOptions(wordCount: 5, separator: ".", capitalize: true, appendDigit: true))).value
            var parts = value.split(separator: ".").map(String.init)
            #expect(parts.count == 5)
            #expect(parts.last!.last!.isNumber)
            parts[4].removeLast()
            for p in parts {
                #expect(p.first!.isUppercase)
                #expect(words.contains(p.lowercased()))
            }
        }
    }

    @Test func passphraseEntropy() {
        let bits = Passphrase.entropy(PassphraseOptions(wordCount: 5, appendDigit: true))
        #expect(abs(bits - (5 * log2(7776) + log2(10))) < 1e-9)
    }

    @Test func pinAvoidsWeakPatterns() throws {
        for weak in ["123456", "654321", "111111", "121212", "123123", "112233", "900101", "311299", "1234", "0000", "1990", "0214"] {
            #expect(PIN.isWeak(weak), "\(weak) should be weak")
        }
        for _ in 0..<300 {
            let pin = try Generator.generate(.pin(PINOptions(length: 6))).value
            #expect(pin.count == 6)
            #expect(pin.allSatisfy { $0.isNumber })
            #expect(!PIN.isWeak(pin))
        }
    }

    @Test func pinEntropyIsHonest() {
        let bits = PIN.entropy(PINOptions(length: 6))
        #expect(bits < log2(1e6))
        #expect(bits > 19.5)
        #expect(PIN.entropy(PINOptions(length: 6, avoidWeakPatterns: false)) == log2(1e6))
    }

    @Test func pronounceableShape() throws {
        let value = try Generator.generate(.pronounceable(PronounceableOptions())).value
        let regex = /^[BDFGHJKLMNPRSTVZ][aeiou]([bdfghjklmnprstvz][aeiou]){2}(-[BDFGHJKLMNPRSTVZ][aeiou]([bdfghjklmnprstvz][aeiou]){2}){2}-\d{2}$/
        #expect(value.wholeMatch(of: regex) != nil, "\(value)")
    }

    @Test func keyFormats() throws {
        let hex = try Generator.generate(.key(KeyOptions(bytes: 32, format: .hex))).value
        #expect(hex.count == 64 && hex.allSatisfy { $0.isHexDigit })

        let b64url = try Generator.generate(.key(KeyOptions(bytes: 32, format: .base64url))).value
        #expect(b64url.count == 43)
        #expect(!b64url.contains { "+/=".contains($0) })

        let b64 = try Generator.generate(.key(KeyOptions(bytes: 32, format: .base64))).value
        #expect(Data(base64Encoded: b64)?.count == 32)

        let uuid = try Generator.generate(.key(KeyOptions(format: .uuid))).value
        #expect(uuid.wholeMatch(of: /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/) != nil)
        #expect(GeneratorConfig.key(KeyOptions(format: .uuid)).entropyBits == 122)
        #expect(GeneratorConfig.key(KeyOptions(bytes: 32)).entropyBits == 256)
    }
}

// MARK: - Strength, presets, coding

@Suite struct MetaTests {
    @Test func strengthThresholds() {
        #expect(Strength(bits: 20) == .weak)
        #expect(Strength(bits: 39.9) == .weak)
        #expect(Strength(bits: 40) == .fair)
        #expect(Strength(bits: 79.9) == .fair)
        #expect(Strength(bits: 85) == .strong)
        #expect(Strength(bits: 100) == .max)
        #expect(Strength.max.filledSegments == 4)
    }

    @Test func crackTimeMagnitudes() {
        #expect(CrackTime.magnitude(forBits: 20) == .instant)
        #expect(CrackTime.magnitude(forBits: 47) == .minutes(2))
        #expect(CrackTime.magnitude(forBits: 131) == .powerOfTenYears(exponent: 20))
    }

    @Test func builtInPresetsAllGenerate() throws {
        #expect(Set(Preset.builtIns.map(\.id)).count == Preset.builtIns.count)
        for preset in Preset.builtIns {
            _ = try Generator.generate(preset.config)
        }
        #expect(Preset.builtIn(id: "default")?.config.entropyBits ?? 0 > 130)
    }

    @Test func configRoundTripsThroughJSON() throws {
        for preset in Preset.builtIns {
            let data = try JSONEncoder().encode(preset)
            #expect(try JSONDecoder().decode(Preset.self, from: data) == preset)
        }
    }
}
