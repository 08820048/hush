import Foundation

/// A named configuration ("recipe"). Built-in presets have stable ids the CLI accepts.
public struct Preset: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var config: GeneratorConfig
    public var isBuiltIn: Bool

    public init(id: String = UUID().uuidString, name: String, config: GeneratorConfig, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.config = config
        self.isBuiltIn = isBuiltIn
    }

    public static let builtIns: [Preset] = [
        Preset(id: "default", name: "Strong default",
               config: .random(RandomOptions()), isBuiltIn: true),
        Preset(id: "compatible", name: "Compatible",
               config: .random(RandomOptions(length: 16, symbolSet: CharacterPools.compatibleSymbols, excludeAmbiguous: true)),
               isBuiltIn: true),
        Preset(id: "wifi", name: "Wi-Fi",
               config: .passphrase(PassphraseOptions(wordCount: 5, separator: "-", capitalize: true, appendDigit: true)),
               isBuiltIn: true),
        Preset(id: "pin6", name: "6-digit PIN",
               config: .pin(PINOptions(length: 6)), isBuiltIn: true),
        Preset(id: "devkey", name: "Developer key",
               config: .key(KeyOptions(bytes: 32, format: .base64url)), isBuiltIn: true),
        Preset(id: "memorable", name: "Memorable",
               config: .passphrase(PassphraseOptions(wordCount: 6, separator: "-", capitalize: true, appendDigit: true)),
               isBuiltIn: true),
    ]

    public static func builtIn(id: String) -> Preset? {
        builtIns.first { $0.id == id }
    }
}
