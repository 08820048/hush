import Foundation

/// The `hush://` URL scheme, for launchers and scripts (Alfred, Raycast, `open`, shell).
///
///     hush://open                                  show the panel
///     hush://generate                              generate with the default config and copy it
///     hush://generate?preset=wifi                  start from a preset
///     hush://generate?mode=random&length=24&symbols=0
///     hush://generate?mode=passphrase&words=6&separator=space
///     hush://generate?mode=key&bytes=64&format=hex
///     hush://generate?site=example.com             follow a website's known password rules
///     hush://generate?rules=minlength:8;required:digit   follow Apple password rules text
///     hush://generate?...&copy=0                   show the result in the panel instead of copying
///
/// A URL can only produce a new secret. It can never read back one that was generated earlier.
public enum HushURL {
    public static let scheme = "hush"

    public enum Action: Equatable, Sendable {
        case open
        case generate(GeneratorConfig, copy: Bool)
    }

    public enum ParseError: Error, Equatable, Sendable, CustomStringConvertible {
        case notHushURL
        case unknownAction(String)
        case unknownPreset(String)
        case unknownMode(String)
        case unknownParameter(String)
        case invalidValue(name: String, value: String)

        public var description: String {
            switch self {
            case .notHushURL: "Not a hush:// URL"
            case .unknownAction(let a): "Unknown action “\(a)”. Use open or generate."
            case .unknownPreset(let p): "Unknown preset “\(p)”"
            case .unknownMode(let m): "Unknown mode “\(m)”. Use random, passphrase, pin, pronounceable or key."
            case .unknownParameter(let p): "Unknown parameter “\(p)” for this mode"
            case .invalidValue(let n, let v): "Invalid value “\(v)” for \(n)"
            }
        }
    }

    /// Parses a URL. `presets` resolves `preset=` (built-in and custom presets).
    public static func parse(_ url: URL, presets: [Preset] = Preset.builtIns) throws -> Action {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw ParseError.notHushURL }
        // Accept both hush://generate?… (host) and hush:generate?… (path). URLComponents is used
        // instead of URL.path, whose result for the second form differs between macOS versions.
        let action = (components.host ?? components.path).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        switch action {
        case "open", "":
            return .open
        case "generate":
            break
        default:
            throw ParseError.unknownAction(action)
        }

        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            params[item.name.lowercased()] = item.value ?? ""
        }
        var reader = Reader(params: params)
        let copy = try reader.bool("copy") ?? true

        var config: GeneratorConfig
        if let site = reader.take("site") {
            // Unknown sites fall back to the defaults, which most sites accept.
            config = .random(SiteRules.lookup(site)?.rules.randomOptions() ?? RandomOptions())
        } else if let text = reader.take("rules") {
            config = .random(PasswordRules(parsing: text).randomOptions())
        } else if let id = reader.take("preset") {
            guard let preset = presets.first(where: { $0.id == id }) else { throw ParseError.unknownPreset(id) }
            config = preset.config
        } else if let name = reader.take("mode") {
            guard let mode = Mode(urlName: name) else { throw ParseError.unknownMode(name) }
            config = .defaultConfig(for: mode)
        } else {
            config = .defaultConfig(for: .random)
        }

        switch config {
        case .random(var o):
            o.length = try reader.int("length", in: RandomOptions.lengthRange) ?? o.length
            o.uppercase = try reader.bool("upper") ?? o.uppercase
            o.lowercase = try reader.bool("lower") ?? o.lowercase
            o.digits = try reader.bool("digits") ?? o.digits
            o.symbols = try reader.bool("symbols") ?? o.symbols
            if let set = reader.take("symbolset") {
                guard !set.isEmpty else { throw ParseError.invalidValue(name: "symbolset", value: set) }
                o.symbolSet = set
            }
            o.excludeAmbiguous = try reader.bool("exclude-ambiguous") ?? o.excludeAmbiguous
            o.excludedCharacters = reader.take("exclude") ?? o.excludedCharacters
            o.requireEachClass = try reader.bool("require-each") ?? o.requireEachClass
            config = .random(o)
        case .passphrase(var o):
            o.wordCount = try reader.int("words", in: PassphraseOptions.wordCountRange) ?? o.wordCount
            if let sep = reader.take("separator") {
                let value = sep.lowercased() == "space" ? " " : sep
                guard PassphraseOptions.separators.contains(value) else { throw ParseError.invalidValue(name: "separator", value: sep) }
                o.separator = value
            }
            o.capitalize = try reader.bool("capitalize") ?? o.capitalize
            o.appendDigit = try reader.bool("digit") ?? o.appendDigit
            config = .passphrase(o)
        case .pin(var o):
            o.length = try reader.int("length", in: PINOptions.lengthRange) ?? o.length
            o.avoidWeakPatterns = try reader.bool("avoid-weak") ?? o.avoidWeakPatterns
            config = .pin(o)
        case .pronounceable(var o):
            o.groups = try reader.int("groups", in: PronounceableOptions.groupRange) ?? o.groups
            o.digits = try reader.int("digits", in: 0...6) ?? o.digits
            config = .pronounceable(o)
        case .key(var o):
            o.bytes = try reader.int("bytes", in: KeyOptions.byteRange) ?? o.bytes
            if let f = reader.take("format") {
                guard let format = KeyFormat(rawValue: f.lowercased()) else { throw ParseError.invalidValue(name: "format", value: f) }
                o.format = format
            }
            config = .key(o)
        }

        // Anything left over is a typo or belongs to another mode; say so instead of ignoring it.
        if let leftover = reader.remaining.sorted().first { throw ParseError.unknownParameter(leftover) }
        return .generate(config, copy: copy)
    }

    private struct Reader {
        var params: [String: String]
        var remaining: Set<String> { Set(params.keys) }

        mutating func take(_ name: String) -> String? {
            params.removeValue(forKey: name)
        }

        mutating func int(_ name: String, in range: ClosedRange<Int>) throws -> Int? {
            guard let raw = take(name) else { return nil }
            guard let value = Int(raw), range.contains(value) else { throw ParseError.invalidValue(name: name, value: raw) }
            return value
        }

        mutating func bool(_ name: String) throws -> Bool? {
            guard let raw = take(name) else { return nil }
            switch raw.lowercased() {
            case "1", "true", "yes", "on", "": return true
            case "0", "false", "no", "off": return false
            default: throw ParseError.invalidValue(name: name, value: raw)
            }
        }
    }
}

extension Mode {
    /// Mode names accepted in URLs and by the CLI, including the CLI's short aliases.
    public init?(urlName: String) {
        switch urlName.lowercased() {
        case "random": self = .random
        case "passphrase", "phrase": self = .passphrase
        case "pin": self = .pin
        case "pronounceable", "say", "syllables": self = .pronounceable
        case "key": self = .key
        default: return nil
        }
    }
}
