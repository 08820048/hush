import AppKit
import HushCore
import ServiceManagement
import SwiftUI

/// User preferences. Stored in UserDefaults. Passwords are never stored here or anywhere else.
@MainActor
final class AppSettings: ObservableObject {
    enum Appearance: String, CaseIterable {
        case system, light, dark

        var title: String {
            switch self {
            case .system: String(localized: "System")
            case .light: String(localized: "Light")
            case .dark: String(localized: "Dark")
            }
        }
    }

    static let clearIntervals = [10, 30, 60, 90, 0] // 0 = never

    private let defaults: UserDefaults

    @Published var clearAfterSeconds: Int { didSet { defaults.set(clearAfterSeconds, forKey: Keys.clearAfter) } }
    @Published var concealFromClipboardManagers: Bool { didSet { defaults.set(concealFromClipboardManagers, forKey: Keys.conceal) } }
    @Published var historyEnabled: Bool { didSet { defaults.set(historyEnabled, forKey: Keys.history) } }
    @Published var showCopyToast: Bool { didSet { defaults.set(showCopyToast, forKey: Keys.toast) } }
    @Published var animationsEnabled: Bool { didSet { defaults.set(animationsEnabled, forKey: Keys.animations) } }
    @Published var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
        }
    }
    @Published var menuBarPresetID: String { didSet { defaults.set(menuBarPresetID, forKey: Keys.menuBarPreset) } }
    @Published var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded) } }
    @Published private(set) var launchAtLogin: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.clearAfter: 30,
            Keys.conceal: true,
            Keys.history: true,
            Keys.toast: false,
            Keys.animations: true,
            Keys.appearance: Appearance.system.rawValue,
            Keys.menuBarPreset: "default",
            Keys.onboarded: false,
        ])
        clearAfterSeconds = defaults.integer(forKey: Keys.clearAfter)
        concealFromClipboardManagers = defaults.bool(forKey: Keys.conceal)
        historyEnabled = defaults.bool(forKey: Keys.history)
        showCopyToast = defaults.bool(forKey: Keys.toast)
        animationsEnabled = defaults.bool(forKey: Keys.animations)
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        menuBarPresetID = defaults.string(forKey: Keys.menuBarPreset) ?? "default"
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Generator state

    var lastMode: Mode {
        get { Mode(rawValue: defaults.string(forKey: Keys.lastMode) ?? "") ?? .random }
        set { defaults.set(newValue.rawValue, forKey: Keys.lastMode) }
    }

    func storedConfig(for mode: Mode) -> GeneratorConfig {
        guard let data = defaults.data(forKey: Keys.config(mode)),
              let config = try? JSONDecoder().decode(GeneratorConfig.self, from: data),
              config.mode == mode
        else { return .defaultConfig(for: mode) }
        return config
    }

    func store(_ config: GeneratorConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: Keys.config(config.mode))
        }
    }

    var menuBarPreset: Preset { Preset.builtIn(id: menuBarPresetID) ?? Preset.builtIns[0] }

    // MARK: System integration

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Hush: launch at login change failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private enum Keys {
        static let clearAfter = "clearAfterSeconds"
        static let conceal = "concealFromClipboardManagers"
        static let history = "historyEnabled"
        static let toast = "showCopyToast"
        static let animations = "animationsEnabled"
        static let appearance = "appearance"
        static let menuBarPreset = "menuBarPresetID"
        static let onboarded = "hasCompletedOnboarding"
        static let lastMode = "lastMode"
        static func config(_ mode: Mode) -> String { "config.\(mode.rawValue)" }
    }
}
