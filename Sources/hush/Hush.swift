import ArgumentParser
import Foundation
import HushCore

@main
struct Hush: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hush",
        abstract: "Quietly generate strong passwords, passphrases, PINs and keys. Offline, nothing stored.",
        version: "0.1.0",
        subcommands: [RandomCommand.self, PhraseCommand.self, PINCommand.self, SayCommand.self, KeyCommand.self, PresetsCommand.self],
        defaultSubcommand: RandomCommand.self
    )
}

struct OutputOptions: ParsableArguments {
    @Option(name: [.customShort("n"), .customLong("count")], help: "How many to generate.")
    var count: Int = 1

    @Flag(help: "Print JSON lines with value, entropy and strength.")
    var json = false

    @Flag(name: .shortAndLong, help: "Print entropy and strength to stderr.")
    var verbose = false

    func validate() throws {
        guard (1...1_000).contains(count) else { throw ValidationError("--count must be between 1 and 1000.") }
    }

    func emit(_ config: GeneratorConfig) throws {
        for _ in 0..<count {
            let secret: Secret
            do { secret = try Generator.generate(config) } catch let error as GeneratorError {
                throw ValidationError(error.description)
            }
            if json {
                let object: [String: Any] = [
                    "value": secret.value,
                    "entropyBits": NSDecimalNumber(string: String(format: "%.1f", secret.entropyBits)),
                    "strength": "\(secret.strength)",
                    "mode": secret.config.mode.rawValue,
                ]
                let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
                print(String(decoding: data, as: UTF8.self))
            } else {
                print(secret.value)
            }
        }
        if verbose {
            fflush(stdout)
            let bits = config.entropyBits
            let line = String(format: "%.1f bits · %@ · %@\n", bits, "\(Strength(bits: bits))", describe(CrackTime.magnitude(forBits: bits)))
            FileHandle.standardError.write(Data(line.utf8))
        }
    }
}

func describe(_ magnitude: CrackTime.Magnitude) -> String {
    switch magnitude {
    case .instant: "cracked instantly offline"
    case .seconds(let n): "~\(n) s to exhaust offline"
    case .minutes(let n): "~\(n) min to exhaust offline"
    case .hours(let n): "~\(n) h to exhaust offline"
    case .days(let n): "~\(n) days to exhaust offline"
    case .years(let n): "~\(n) years to exhaust offline"
    case .powerOfTenYears(let e): "~10^\(e) years to exhaust offline"
    }
}

struct RandomCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "random", abstract: "Random characters (default).")

    @Option(name: .shortAndLong, help: "Length, 4–128.")
    var length: Int?

    @Flag(name: .customLong("no-upper"), help: "Leave out A–Z.") var noUpper = false
    @Flag(name: .customLong("no-lower"), help: "Leave out a–z.") var noLower = false
    @Flag(name: .customLong("no-digits"), help: "Leave out 0–9.") var noDigits = false
    @Flag(name: .customLong("no-symbols"), help: "Leave out symbols.") var noSymbols = false

    @Option(name: .customLong("symbols"), help: "Symbols to draw from, e.g. '!@#$%'.")
    var symbolSet: String?

    @Flag(name: [.customShort("a"), .customLong("exclude-ambiguous")], help: "Leave out 0 O o 1 l I | ` ' \".")
    var excludeAmbiguous = false

    @Option(name: .customLong("exclude"), help: "Characters never to use.")
    var exclude: String?

    @Flag(name: .customLong("no-require-each"), help: "Don't force at least one of every enabled class.")
    var noRequireEach = false

    @Option(name: .shortAndLong, help: "Start from a built-in preset (see `hush presets`).")
    var preset: String?

    @OptionGroup var output: OutputOptions

    func run() throws {
        var options = RandomOptions()
        if let preset {
            guard let found = Preset.builtIn(id: preset) else {
                throw ValidationError("Unknown preset '\(preset)'. Run `hush presets` to list them.")
            }
            guard case .random(let presetOptions) = found.config else {
                try output.emit(found.config)
                return
            }
            options = presetOptions
        }
        if let length { options.length = length }
        if noUpper { options.uppercase = false }
        if noLower { options.lowercase = false }
        if noDigits { options.digits = false }
        if noSymbols { options.symbols = false }
        if let symbolSet { options.symbolSet = symbolSet }
        if excludeAmbiguous { options.excludeAmbiguous = true }
        if let exclude { options.excludedCharacters = exclude }
        if noRequireEach { options.requireEachClass = false }
        try output.emit(.random(options))
    }
}

struct PhraseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "phrase", abstract: "Words from the EFF list: Velvet-Otter-Ample-Crane-Harbor7.")

    @Option(name: .shortAndLong, help: "Number of words, 3–10.") var words = 5
    @Option(name: .shortAndLong, help: "Separator between words.") var separator = "-"
    @Flag(name: .customLong("lowercase"), help: "Don't capitalise words.") var lowercase = false
    @Flag(name: .customLong("no-digit"), help: "Don't append a digit.") var noDigit = false
    @OptionGroup var output: OutputOptions

    func run() throws {
        try output.emit(.passphrase(PassphraseOptions(wordCount: words, separator: separator, capitalize: !lowercase, appendDigit: !noDigit)))
    }
}

struct PINCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "pin", abstract: "Digits only, avoiding 123456, dates and repeats.")

    @Argument(help: "Number of digits, 4–12.") var length = 6
    @Flag(name: .customLong("allow-weak"), help: "Allow repeats, runs and dates.") var allowWeak = false
    @OptionGroup var output: OutputOptions

    func run() throws {
        try output.emit(.pin(PINOptions(length: length, avoidWeakPatterns: !allowWeak)))
    }
}

struct SayCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "say", abstract: "Pronounceable syllables: Tobavu-Kimeso-Ragune-42.")

    @Option(name: .shortAndLong, help: "Number of syllable groups, 2–6.") var groups = 3
    @Option(name: .shortAndLong, help: "Digits appended at the end.") var digits = 2
    @OptionGroup var output: OutputOptions

    func run() throws {
        try output.emit(.pronounceable(PronounceableOptions(groups: groups, digits: digits)))
    }
}

struct KeyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "key", abstract: "Random bytes for API secrets and tokens.")

    @Option(name: .shortAndLong, help: "Number of random bytes, 8–128.") var bytes = 32
    @Option(name: .shortAndLong, help: "hex, base64, base64url or uuid.") var format: KeyFormat = .base64url
    @OptionGroup var output: OutputOptions

    func run() throws {
        try output.emit(.key(KeyOptions(bytes: bytes, format: format)))
    }
}

extension KeyFormat: ExpressibleByArgument {}

struct PresetsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "presets", abstract: "List built-in presets.")

    func run() {
        for preset in Preset.builtIns {
            let bits = String(format: "%5.1f bits", preset.config.entropyBits)
            print("\(preset.id.padding(toLength: 12, withPad: " ", startingAt: 0)) \(bits)  \(preset.config.mode.rawValue)")
        }
    }
}
