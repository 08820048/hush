import Foundation
import Testing
@testable import HushCore

@Suite struct HushURLTests {
    private func parse(_ string: String, presets: [Preset] = Preset.builtIns) throws -> HushURL.Action {
        try HushURL.parse(URL(string: string)!, presets: presets)
    }

    @Test func openAndBareScheme() throws {
        #expect(try parse("hush://open") == .open)
        #expect(try parse("hush://") == .open)
    }

    @Test func generateDefaultsToRandomAndCopies() throws {
        #expect(try parse("hush://generate") == .generate(.random(RandomOptions()), copy: true))
        #expect(try parse("hush:generate") == .generate(.random(RandomOptions()), copy: true))
    }

    @Test func randomOverrides() throws {
        let action = try parse("hush://generate?mode=random&length=32&symbols=0&exclude-ambiguous=1&copy=0")
        var expected = RandomOptions()
        expected.length = 32
        expected.symbols = false
        expected.excludeAmbiguous = true
        #expect(action == .generate(.random(expected), copy: false))
    }

    @Test func passphraseWithSpaceSeparatorAndAlias() throws {
        let action = try parse("hush://generate?mode=phrase&words=6&separator=space&capitalize=false")
        #expect(action == .generate(.passphrase(PassphraseOptions(wordCount: 6, separator: " ", capitalize: false)), copy: true))
    }

    @Test func keyFormat() throws {
        let action = try parse("hush://generate?mode=key&bytes=64&format=HEX")
        #expect(action == .generate(.key(KeyOptions(bytes: 64, format: .hex)), copy: true))
    }

    @Test func presetIsTheStartingPoint() throws {
        let action = try parse("hush://generate?preset=pin6&length=8")
        #expect(action == .generate(.pin(PINOptions(length: 8)), copy: true))

        let custom = Preset(id: "team", name: "Team", config: .random(RandomOptions(length: 40)))
        #expect(try parse("hush://generate?preset=team", presets: [custom]) == .generate(custom.config, copy: true))
    }

    @Test func errorsAreSpecific() {
        #expect(throws: HushURL.ParseError.notHushURL) { try parse("https://example.com") }
        #expect(throws: HushURL.ParseError.unknownAction("delete")) { try parse("hush://delete") }
        #expect(throws: HushURL.ParseError.unknownPreset("nope")) { try parse("hush://generate?preset=nope") }
        #expect(throws: HushURL.ParseError.unknownMode("emoji")) { try parse("hush://generate?mode=emoji") }
        #expect(throws: HushURL.ParseError.invalidValue(name: "length", value: "1000")) { try parse("hush://generate?length=1000") }
        #expect(throws: HushURL.ParseError.invalidValue(name: "copy", value: "maybe")) { try parse("hush://generate?copy=maybe") }
        // `words` belongs to passphrase mode, so it is a mistake in random mode.
        #expect(throws: HushURL.ParseError.unknownParameter("words")) { try parse("hush://generate?words=5") }
    }

    @Test func everyParsedConfigGenerates() throws {
        for url in ["hush://generate?mode=pin&length=12", "hush://generate?mode=say&groups=6&digits=0", "hush://generate?mode=key&format=uuid"] {
            guard case .generate(let config, _) = try parse(url) else { Issue.record("expected generate"); continue }
            _ = try Generator.generate(config)
        }
    }
}

@Suite struct PrimarySizeTests {
    @Test func setsTheMainKnobOfEachMode() throws {
        #expect(try GeneratorConfig.defaultConfig(for: .random).withPrimarySize(40).primarySize == 40)
        #expect(try GeneratorConfig.defaultConfig(for: .passphrase).withPrimarySize(8).primarySize == 8)
        #expect(try GeneratorConfig.defaultConfig(for: .pin).withPrimarySize(4).primarySize == 4)
        #expect(try GeneratorConfig.key(KeyOptions(format: .uuid)).withPrimarySize(64).primarySize == nil)
        #expect(throws: GeneratorError.lengthOutOfRange(PINOptions.lengthRange)) {
            try GeneratorConfig.defaultConfig(for: .pin).withPrimarySize(40)
        }
    }
}

@Suite struct HushURLRulesTests {
    @Test func siteAndRulesParameters() throws {
        let site = try HushURL.parse(URL(string: "hush://generate?site=https://www.163.com/")!)
        #expect(site == .generate(.random(SiteRules.lookup("163.com")!.rules.randomOptions()), copy: true))

        let rules = try HushURL.parse(URL(string: "hush://generate?rules=maxlength:%2012;%20required:%20digit&length=10")!)
        guard case .generate(.random(let o), _) = rules else { Issue.record("expected random"); return }
        #expect(o.length == 10)

        // Unknown sites use the defaults instead of failing.
        #expect(try HushURL.parse(URL(string: "hush://generate?site=unknown.example")!) == .generate(.random(RandomOptions()), copy: true))
    }
}
