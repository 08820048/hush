import AppKit
import HushCore
import SwiftUI

/// What the panel shows and everything it can do.
@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let clipboard: ClipboardService
    let history: HistoryStore

    @Published private(set) var mode: Mode
    @Published private(set) var configs: [Mode: GeneratorConfig]
    @Published private(set) var secret: Secret?
    /// What is on screen; differs from `secret.value` only during the reveal animation.
    @Published private(set) var display: String = ""
    @Published var isRevealed = true
    @Published var showsHistory = false
    @Published private(set) var errorMessage: String?
    /// Name of the app that will receive ⌘↩ paste.
    @Published private(set) var targetAppName: String?

    private var revealTask: Task<Void, Never>?

    init(settings: AppSettings, clipboard: ClipboardService, history: HistoryStore) {
        self.settings = settings
        self.clipboard = clipboard
        self.history = history
        mode = settings.lastMode
        configs = Dictionary(uniqueKeysWithValues: Mode.allCases.map { ($0, settings.storedConfig(for: $0)) })
    }

    var config: GeneratorConfig { configs[mode] ?? .defaultConfig(for: mode) }

    /// The built-in preset the current settings match, if any.
    var presetName: String? { Preset.builtIns.first { $0.config == config }?.displayName }

    // MARK: Generating

    func regenerate(animated: Bool = true) {
        do {
            let next = try Generator.generate(config)
            errorMessage = nil
            secret = next
            reveal(next.value, animated: animated)
        } catch let error as GeneratorError {
            errorMessage = error == .emptyCharacterSet ? String(localized: "Turn on at least one character type") : error.description
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        settings.lastMode = newMode
        showsHistory = false
        regenerate()
    }

    func apply(_ preset: Preset) {
        let newMode = preset.config.mode
        configs[newMode] = preset.config
        settings.store(preset.config)
        mode = newMode
        settings.lastMode = newMode
        regenerate()
    }

    func update(_ config: GeneratorConfig) {
        configs[config.mode] = config
        settings.store(config)
        regenerate(animated: false)
    }

    func reroll(at index: Int) {
        guard let secret, let next = try? Generator.reroll(secret, at: index) else { return }
        self.secret = next
        revealTask?.cancel()
        display = next.value
    }

    /// ↑/↓ and the scroll wheel: change the main size knob of the current mode.
    func adjustPrimary(by delta: Int) {
        switch config {
        case .random(var o):
            o.length = clamp(o.length + delta, RandomOptions.lengthRange)
            update(.random(o))
        case .passphrase(var o):
            o.wordCount = clamp(o.wordCount + delta.signum(), PassphraseOptions.wordCountRange)
            update(.passphrase(o))
        case .pin(var o):
            o.length = clamp(o.length + delta.signum(), PINOptions.lengthRange)
            update(.pin(o))
        case .pronounceable(var o):
            o.groups = clamp(o.groups + delta.signum(), PronounceableOptions.groupRange)
            update(.pronounceable(o))
        case .key(var o):
            guard o.format != .uuid else { return }
            o.bytes = clamp(o.bytes + delta * 4, KeyOptions.byteRange)
            update(.key(o))
        }
    }

    // MARK: Delivering

    func noteTargetApp() {
        let front = NSWorkspace.shared.frontmostApplication
        targetAppName = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front?.localizedName
    }

    /// Copies the current secret with clipboard protection.
    func copyCurrent() {
        guard let value = secret?.value else { return }
        copy(value, mode: mode)
    }

    func copy(_ value: String, mode: Mode) {
        clipboard.copy(value, conceal: settings.concealFromClipboardManagers, clearAfter: settings.clearAfterSeconds)
        if settings.historyEnabled { history.add(value, mode: mode) }
        if settings.showCopyToast {
            let seconds = settings.clearAfterSeconds
            Toast.shared.show(seconds > 0 ? String(localized: "Copied · clears in \(seconds) s") : String(localized: "Copied"))
        }
    }

    /// Menu bar left click and preset hotkeys: generate and copy without showing the panel.
    func quickCopy(_ preset: Preset) {
        guard let secret = try? Generator.generate(preset.config) else { return }
        copy(secret.value, mode: preset.config.mode)
    }

    // MARK: Reveal animation

    private func reveal(_ value: String, animated: Bool) {
        revealTask?.cancel()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated, settings.animationsEnabled, !reduceMotion, value.count <= 64 else {
            display = value
            return
        }
        let target = Array(value)
        let pool = Array(Set(target)).isEmpty ? ["•"] : Array(Set(target))
        let frames = 9
        revealTask = Task { [weak self] in
            var rng = SecureRandom()
            for frame in 0...frames {
                guard let self, !Task.isCancelled else { return }
                let settled = target.count * frame / frames
                let noise = (settled..<target.count).map { i -> Character in
                    target[i].isWhitespace || target[i] == "-" ? target[i] : rng.pick(pool)
                }
                self.display = String(target[..<settled]) + String(noise)
                try? await Task.sleep(for: .milliseconds(32))
            }
            self?.display = value
        }
    }

    private func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
