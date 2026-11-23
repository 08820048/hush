import Foundation
import HushCore
import KeyboardShortcuts

/// Built-in presets plus the user's own. Custom presets are recipes (settings), never
/// passwords, so they are stored in UserDefaults like any other preference.
@MainActor
final class PresetStore: ObservableObject {
    static let maxNameLength = 40

    @Published private(set) var custom: [Preset]
    /// Called after any change, so global shortcuts can be re-registered.
    var onChange: (() -> Void)?

    private let defaults: UserDefaults
    private static let key = "customPresets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([Preset].self, from: data) {
            custom = stored
        } else {
            custom = []
        }
    }

    var all: [Preset] { Preset.builtIns + custom }

    func preset(id: String) -> Preset? {
        all.first { $0.id == id }
    }

    /// The preset whose settings match `config` exactly, preferring built-ins.
    func matching(_ config: GeneratorConfig) -> Preset? {
        all.first { $0.config == config }
    }

    // MARK: Editing

    @discardableResult
    func add(name: String, config: GeneratorConfig) -> Preset? {
        guard let name = Self.clean(name) else { return nil }
        let preset = Preset(id: "custom-" + UUID().uuidString.prefix(8).lowercased(), name: name, config: config)
        custom.append(preset)
        save()
        return preset
    }

    func rename(_ id: String, to name: String) {
        guard let name = Self.clean(name), let index = custom.firstIndex(where: { $0.id == id }) else { return }
        custom[index].name = name
        save()
    }

    func delete(_ id: String) {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return }
        custom.remove(at: index)
        // Forget its global shortcut, so it doesn't fire for a preset that no longer exists.
        KeyboardShortcuts.reset(.preset(id))
        save()
    }

    func move(_ id: String, by offset: Int) {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard custom.indices.contains(target) else { return }
        custom.swapAt(index, target)
        save()
    }

    func canMove(_ id: String, by offset: Int) -> Bool {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return false }
        return custom.indices.contains(index + offset)
    }

    static func clean(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(custom) {
            defaults.set(data, forKey: Self.key)
        }
        onChange?()
    }
}
