import AppIntents
import HushCore

// Shortcuts actions: "Generate Password" and "Generate with Preset". Both return the new
// secret as text and can optionally copy it with the same protection as the app
// (concealed from clipboard managers, cleared after the configured delay).

/// The running app's model, so intents can copy through the protected clipboard.
@MainActor
enum IntentBridge {
    static weak var model: AppModel?
}

enum PasswordType: String, AppEnum {
    case random, passphrase, pin, pronounceable, key

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Password Type"
    static let caseDisplayRepresentations: [PasswordType: DisplayRepresentation] = [
        .random: "Random",
        .passphrase: "Phrase",
        .pin: "PIN",
        .pronounceable: "Syllables",
        .key: "Key",
    ]

    var mode: Mode { Mode(rawValue: rawValue) ?? .random }
}

struct GeneratePasswordIntent: AppIntent {
    static let title: LocalizedStringResource = "Generate Password"
    static let description = IntentDescription("Generates a new password with Hush and returns it. Nothing is stored.")

    @Parameter(title: "Type", default: .random)
    var type: PasswordType

    @Parameter(
        title: "Size",
        description: "Characters for Random, words for Phrase, digits for PIN, groups for Syllables, bytes for Key. Leave empty for the default."
    )
    var size: Int?

    @Parameter(title: "Copy to Clipboard", default: false)
    var copy: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Generate a \(\.$type) password") {
            \.$size
            \.$copy
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var config = GeneratorConfig.defaultConfig(for: type.mode)
        if let size { config = try config.withPrimarySize(size) }
        let secret = try Generator.generate(config)
        if copy { IntentBridge.model?.copy(secret.value, mode: config.mode) }
        return .result(value: secret.value)
    }
}

struct GenerateWithPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Generate with Preset"
    static let description = IntentDescription("Generates a new password from one of your Hush presets and returns it. Nothing is stored.")

    @Parameter(title: "Preset")
    var preset: PresetEntity

    @Parameter(title: "Copy to Clipboard", default: false)
    var copy: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Generate a password with \(\.$preset)") {
            \.$copy
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let preset = PresetEntity.store.preset(id: preset.id) else {
            throw $preset.needsValueError()
        }
        let secret = try Generator.generate(preset.config)
        if copy { IntentBridge.model?.copy(secret.value, mode: preset.config.mode) }
        return .result(value: secret.value)
    }
}

struct PresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Preset"
    static let defaultQuery = PresetQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    /// The app's store when it is running normally, otherwise a fresh read of saved presets.
    @MainActor
    static var store: PresetStore { IntentBridge.model?.presets ?? PresetStore() }

    @MainActor
    init(_ preset: Preset) {
        id = preset.id
        name = preset.displayName
    }
}

struct PresetQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PresetEntity] {
        await MainActor.run {
            let store = PresetEntity.store
            return identifiers.compactMap { store.preset(id: $0) }.map(PresetEntity.init)
        }
    }

    func suggestedEntities() async throws -> [PresetEntity] {
        await MainActor.run { PresetEntity.store.all.map(PresetEntity.init) }
    }
}

struct HushShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GeneratePasswordIntent(),
            phrases: ["Generate a password with \(.applicationName)", "New \(.applicationName) password"],
            shortTitle: "Generate Password",
            systemImageName: "key"
        )
        AppShortcut(
            intent: GenerateWithPresetIntent(),
            phrases: ["Generate a \(.applicationName) password with \(\.$preset)"],
            shortTitle: "Generate with Preset",
            systemImageName: "tag"
        )
    }
}
