import AppKit
import HushCore
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var clipboard: ClipboardService!
    private var history: HistoryStore!
    private var presets: PresetStore!
    private var model: AppModel!
    private var panel: PanelController!
    private var statusItem: StatusItemController!
    private var largeType: LargeTypeController!
    private var settingsWindow: SettingsWindowController!
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains("--render-snapshots") {
            SnapshotRenderer.run()
        }
        #endif
        settings = AppSettings()
        settings.applyAppearance()
        clipboard = ClipboardService()
        history = HistoryStore()
        presets = PresetStore()
        model = AppModel(settings: settings, clipboard: clipboard, history: history, presets: presets)
        IntentBridge.model = model
        largeType = LargeTypeController()
        settingsWindow = SettingsWindowController(settings: settings, presets: presets)

        panel = PanelController(model: model, history: history)
        panel.onShowLargeType = { [weak self] page in
            guard let self, let value = self.model.secret?.value else { return }
            self.largeType.show(value, page: page)
        }
        panel.onShowSettings = { [weak self] in self?.settingsWindow.show() }

        statusItem = StatusItemController(model: model)
        statusItem.onOpenPanel = { [weak self] in self?.panel.show() }
        statusItem.onOpenSettings = { [weak self] in self?.settingsWindow.show() }

        registerShortcuts()
        presets.onChange = { [weak self] in self?.registerShortcuts() }

        if !settings.hasCompletedOnboarding {
            onboarding = OnboardingWindowController(settings: settings)
            onboarding?.show()
        }
    }

    /// (Re-)registers every global shortcut. Runs again whenever custom presets change.
    private func registerShortcuts() {
        KeyboardShortcuts.removeAllHandlers()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in self?.panel.toggle() }
        KeyboardShortcuts.onKeyUp(for: .clearClipboard) { [weak self] in self?.clipboard.clearIfOwned() }
        for preset in presets.all {
            let id = preset.id
            KeyboardShortcuts.onKeyUp(for: .preset(id)) { [weak self] in
                // Look the preset up at press time so renames and edits are picked up.
                guard let self, let preset = self.presets.preset(id: id) else { return }
                self.model.quickCopy(preset)
                self.statusItem.flashCopied()
            }
        }
    }

    // MARK: hush:// URLs

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url) }
    }

    private func handle(_ url: URL) {
        do {
            switch try HushURL.parse(url, presets: presets.all) {
            case .open:
                showPanelAfterURL()
            case .generate(let config, copy: true):
                let secret = try Generator.generate(config)
                model.copy(secret.value, mode: config.mode)
                statusItem.flashCopied()
            case .generate(let config, copy: false):
                model.load(config)
                showPanelAfterURL()
            }
        } catch let error as HushURL.ParseError {
            Toast.shared.show(error.description, icon: .flag)
        } catch {
            Toast.shared.show(String(localized: "Turn on at least one character type"), icon: .flag)
        }
    }

    /// Opening a URL briefly moves focus around while LaunchServices delivers it. Showing the
    /// panel right away can lose key status in that shuffle, and losing key closes the panel.
    private func showPanelAfterURL() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.panel.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Leave nothing behind.
        clipboard.clearIfOwned()
        history.clear()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return false
    }
}
