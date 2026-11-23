import Foundation

/// A shareable file of presets, for teams that want the same password recipes:
///
///     {
///       "format": "hush-presets",
///       "version": 1,
///       "presets": [
///         { "name": "Team VPN", "mode": "random", "options": { "length": 24, "symbols": false, ... } }
///       ]
///     }
///
/// Only settings are stored, never passwords. Missing options fall back to their defaults,
/// so hand-written files can stay short.
public enum PresetFile {
    public static let format = "hush-presets"
    public static let version = 1
    public static let fileExtension = "json"

    public struct Entry: Equatable, Sendable {
        public var name: String
        public var config: GeneratorConfig

        public init(name: String, config: GeneratorConfig) {
            self.name = name
            self.config = config
        }
    }

    public enum ReadError: Error, Equatable, Sendable, CustomStringConvertible {
        case notJSON
        case wrongFormat
        case unsupportedVersion(Int)
        case invalidPreset(index: Int, reason: String)

        public var description: String {
            switch self {
            case .notJSON: "The file is not valid JSON."
            case .wrongFormat: "The file is not a Hush presets file."
            case .unsupportedVersion(let v): "Presets file version \(v) is newer than this version of Hush supports."
            case .invalidPreset(let i, let reason): "Preset \(i + 1): \(reason)"
            }
        }
    }

    public static func write(_ entries: [Entry]) throws -> Data {
        let file = FileModel(format: format, version: version, presets: entries.map(EntryModel.init))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    public static func read(_ data: Data) throws -> [Entry] {
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else { throw ReadError.notJSON }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: data) } catch { throw ReadError.wrongFormat }
        guard header.format == format else { throw ReadError.wrongFormat }
        guard header.version <= version else { throw ReadError.unsupportedVersion(header.version) }

        let raw: RawFile
        do { raw = try JSONDecoder().decode(RawFile.self, from: data) } catch { throw ReadError.wrongFormat }

        return try raw.presets.enumerated().map { index, item in
            let entry: EntryModel
            do { entry = try JSONDecoder().decode(EntryModel.self, from: JSONSerialization.data(withJSONObject: item.value)) } catch {
                throw ReadError.invalidPreset(index: index, reason: describe(error))
            }
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw ReadError.invalidPreset(index: index, reason: "the name is empty") }
            do { _ = try Generator.generate(entry.config) } catch {
                throw ReadError.invalidPreset(index: index, reason: "\(error)")
            }
            return Entry(name: name, config: entry.config)
        }
    }

    // MARK: File model

    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    private struct FileModel: Encodable {
        let format: String
        let version: Int
        let presets: [EntryModel]
    }

    /// Decodes the preset list as raw JSON first, so one bad entry can be reported by position.
    private struct RawFile: Decodable {
        let presets: [AnyJSON]
    }

    private struct AnyJSON: Decodable {
        let value: Any
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { value = NSNull() }
            else if let b = try? c.decode(Bool.self) { value = b }
            else if let i = try? c.decode(Int.self) { value = i }
            else if let d = try? c.decode(Double.self) { value = d }
            else if let s = try? c.decode(String.self) { value = s }
            else if let a = try? c.decode([AnyJSON].self) { value = a.map(\.value) }
            else { value = try c.decode([String: AnyJSON].self).mapValues(\.value) }
        }
    }

    private struct EntryModel: Codable {
        var name: String
        var config: GeneratorConfig

        enum CodingKeys: String, CodingKey { case name, mode, options }

        init(_ entry: Entry) {
            name = entry.name
            config = entry.config
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            let modeName = try c.decode(String.self, forKey: .mode)
            guard let mode = Mode(urlName: modeName) else {
                throw DecodingError.dataCorruptedError(forKey: .mode, in: c, debugDescription: "unknown mode “\(modeName)”")
            }
            let hasOptions = c.contains(.options)
            switch mode {
            case .random: config = .random(hasOptions ? try c.decode(RandomOptions.self, forKey: .options) : RandomOptions())
            case .passphrase: config = .passphrase(hasOptions ? try c.decode(PassphraseOptions.self, forKey: .options) : PassphraseOptions())
            case .pin: config = .pin(hasOptions ? try c.decode(PINOptions.self, forKey: .options) : PINOptions())
            case .pronounceable: config = .pronounceable(hasOptions ? try c.decode(PronounceableOptions.self, forKey: .options) : PronounceableOptions())
            case .key: config = .key(hasOptions ? try c.decode(KeyOptions.self, forKey: .options) : KeyOptions())
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(config.mode.rawValue, forKey: .mode)
            switch config {
            case .random(let o): try c.encode(o, forKey: .options)
            case .passphrase(let o): try c.encode(o, forKey: .options)
            case .pin(let o): try c.encode(o, forKey: .options)
            case .pronounceable(let o): try c.encode(o, forKey: .options)
            case .key(let o): try c.encode(o, forKey: .options)
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, _): "missing “\(key.stringValue)”"
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            "wrong value for “\(context.codingPath.last?.stringValue ?? "?")”"
        case DecodingError.dataCorrupted(let context): context.debugDescription
        default: "\(error)"
        }
    }
}
