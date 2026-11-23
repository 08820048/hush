import Foundation
import Testing
@testable import HushCore

@Suite struct PasswordRulesTests {
    @Test func parsesPropertiesAndClasses() {
        let rules = PasswordRules(parsing: "minlength: 8; maxlength: 16; required: lower, upper; required: digit; allowed: [-!#]; max-consecutive: 2;")
        #expect(rules.minLength == 8)
        #expect(rules.maxLength == 16)
        #expect(rules.maxConsecutive == 2)
        #expect(rules.required.count == 2)
        #expect(rules.required[0] == PasswordRules.Classes.lower.union(PasswordRules.Classes.upper))
        #expect(rules.allowed == Set("-!#"))
    }

    @Test func customSetsKeepClosingBracketAndSemicolon() {
        // "]]" means "]" is a member; ";" inside brackets does not end the statement.
        let rules = PasswordRules(parsing: "required: [;=?@[]]; minlength: 6")
        #expect(rules.required == [Set(";=?@[]")])
        #expect(rules.minLength == 6)
    }

    @Test func repeatedLimitsTakeTheStrictest() {
        let rules = PasswordRules(parsing: "minlength: 6; minlength: 10; maxlength: 30; maxlength: 20;")
        #expect(rules.minLength == 10 && rules.maxLength == 20)
    }

    @Test func noCharacterRulesMeansPrintableASCII() {
        #expect(PasswordRules(parsing: "minlength: 8").permittedCharacters == PasswordRules.Classes.asciiPrintable)
    }

    @Test func lengthFollowsLimits() {
        #expect(PasswordRules(parsing: "maxlength: 12").randomOptions().length == 12)
        #expect(PasswordRules(parsing: "minlength: 32").randomOptions().length == 32)
        #expect(PasswordRules(parsing: "minlength: 8").randomOptions().length == 20)
    }

    /// Every bundled website rule must parse and always yield compliant passwords.
    @Test func everyBundledSiteGeneratesCompliantPasswords() throws {
        #expect(SiteRules.count > 400)
        var rng = SplitMix64(seed: 7)
        var checked = 0
        for domain in SiteRules.allDomainsForTesting {
            let match = try #require(SiteRules.lookup(domain))
            let options = match.rules.randomOptions()
            for _ in 0..<20 {
                let password = try RandomPassword.generate(options, using: &rng)
                if !match.rules.accepts(password) {
                    Issue.record("\(domain): \(password) breaks \(match.rulesText)")
                    break
                }
            }
            let bits = RandomPassword.entropy(options)
            #expect(bits.isFinite && bits > 0, "\(domain): entropy \(bits)")
            checked += 1
        }
        #expect(checked == SiteRules.count)
    }

    @Test func lookupNormalizesURLsAndWalksUpSubdomains() throws {
        let match = try #require(SiteRules.lookup("https://WWW.163.com/login?x=1"))
        #expect(match.domain == "163.com")
        #expect(SiteRules.lookup("mail.163.com")?.domain == "163.com")
        #expect(SiteRules.lookup("account.xiaomi.com")?.domain == "account.xiaomi.com")
        #expect(SiteRules.lookup("not-a-known-site.example") == nil)
        #expect(SiteRules.lookup("hello") == nil)
    }
}

@Suite struct RandomConstraintTests {
    /// Brute force: count every string the constraints accept and compare with the entropy.
    @Test func entropyIsExactWithGroupsAndRunLimit() throws {
        // Alphabet: A B (upper), 1 2 (digits) → 4 symbols, length 5.
        let options = RandomOptions(
            length: 5, uppercase: true, lowercase: false, digits: true, symbols: false,
            excludedCharacters: "CDEFGHIJKLMNOPQRSTUVWXYZ03456789",
            requireEachClass: true, requiredGroups: ["2"], maxConsecutive: 2
        )
        let constraints = try RandomConstraints(options)
        #expect(constraints.alphabet.count == 4)

        var count = 0
        func visit(_ prefix: [Character]) {
            if prefix.count == options.length {
                if constraints.accepts(prefix) { count += 1 }
                return
            }
            for c in constraints.alphabet { visit(prefix + [c]) }
        }
        visit([])
        #expect(count > 0)
        #expect(abs(RandomPassword.entropy(options) - log2(Double(count))) < 1e-9)
    }

    @Test func generatedPasswordsRespectRunLimitAndGroups() throws {
        var rng = SplitMix64(seed: 11)
        let options = RandomOptions(length: 30, symbols: false, requiredGroups: ["#"], maxConsecutive: 1)
        // "#" is not in the alphabet (symbols off), so it can never be satisfied.
        #expect(throws: GeneratorError.emptyCharacterSet) { try RandomPassword.generate(options, using: &rng) }

        let ok = RandomOptions(length: 30, symbolSet: "#!", requiredGroups: ["#"], maxConsecutive: 1)
        for _ in 0..<200 {
            let p = Array(try RandomPassword.generate(ok, using: &rng))
            #expect(p.contains("#"))
            #expect(RandomPassword.longestRun(p) == 1)
        }
    }

    @Test func decodesSettingsSavedBeforeTheNewFields() throws {
        let old = #"{"length":24,"uppercase":true,"lowercase":true,"digits":true,"symbols":false,"symbolSet":"!","excludeAmbiguous":true,"excludedCharacters":"","requireEachClass":true}"#
        let options = try JSONDecoder().decode(RandomOptions.self, from: Data(old.utf8))
        #expect(options.length == 24 && !options.symbols && options.excludeAmbiguous)
        #expect(options.requiredGroups.isEmpty && options.maxConsecutive == nil)
    }
}
