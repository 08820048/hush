import Foundation
import Testing
@testable import HushCore

@Suite struct PresetFileTests {
    @Test func roundTripsEveryMode() throws {
        let entries = [
            PresetFile.Entry(name: "Team VPN", config: .random(RandomOptions(length: 24, symbolSet: "!#", requiredGroups: ["#"], maxConsecutive: 2))),
            PresetFile.Entry(name: "Router", config: .passphrase(PassphraseOptions(wordCount: 4, separator: "."))),
            PresetFile.Entry(name: "Door", config: .pin(PINOptions(length: 8))),
            PresetFile.Entry(name: "Say", config: .pronounceable(PronounceableOptions(groups: 4))),
            PresetFile.Entry(name: "API", config: .key(KeyOptions(bytes: 48, format: .hex))),
        ]
        let data = try PresetFile.write(entries)
        #expect(try PresetFile.read(data) == entries)

        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""format" : "hush-presets""#))
        #expect(text.contains(#""mode" : "passphrase""#))
    }

    @Test func shortHandWrittenFilesUseDefaults() throws {
        let json = #"""
        { "format": "hush-presets", "version": 1, "presets": [
            { "name": "  Short  ", "mode": "random", "options": { "length": 12 } },
            { "name": "Words", "mode": "phrase" }
        ] }
        """#
        let entries = try PresetFile.read(Data(json.utf8))
        #expect(entries[0].name == "Short")
        #expect(entries[0].config == .random(RandomOptions(length: 12)))
        #expect(entries[1].config == .passphrase(PassphraseOptions()))
    }

    @Test func rejectsOtherFilesWithClearErrors() {
        #expect(throws: PresetFile.ReadError.notJSON) { try PresetFile.read(Data("hello".utf8)) }
        #expect(throws: PresetFile.ReadError.wrongFormat) { try PresetFile.read(Data(#"{"presets": []}"#.utf8)) }
        #expect(throws: PresetFile.ReadError.wrongFormat) { try PresetFile.read(Data(#"{"format": "other", "version": 1, "presets": []}"#.utf8)) }
        #expect(throws: PresetFile.ReadError.unsupportedVersion(9)) {
            try PresetFile.read(Data(#"{"format": "hush-presets", "version": 9, "presets": []}"#.utf8))
        }
    }

    @Test func pointsAtTheBadPreset() {
        let json = #"""
        { "format": "hush-presets", "version": 1, "presets": [
            { "name": "Fine", "mode": "pin" },
            { "name": "Bad", "mode": "random", "options": { "length": 1000 } }
        ] }
        """#
        #expect {
            try PresetFile.read(Data(json.utf8))
        } throws: { error in
            guard case PresetFile.ReadError.invalidPreset(let index, _) = error else { return false }
            return index == 1
        }
        #expect(throws: PresetFile.ReadError.invalidPreset(index: 0, reason: "the name is empty")) {
            try PresetFile.read(Data(#"{"format":"hush-presets","version":1,"presets":[{"name":" ","mode":"pin"}]}"#.utf8))
        }
    }
}
