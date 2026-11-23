import AppKit
import HushCore
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var clipboard: ClipboardService!
    private var history: HistoryStore!
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
        model = AppModel(settings: settings, clipboard: clipboard, history: history)
        largeType = LargeTypeController()
        settingsWindow = SettingsWindowController(settings: settings)

        panel = PanelController(model: model, history: history)
        panel.onShowLargeType = { [weak self] page in
            guard let self, let value = self.model.secret?.value else { return }
            self.largeType.show(value, page: page)
        }
        panel.onShowSettings = { [weak self] in self?.settingsWindow.show() }

        statusItem = StatusItemController(model: model)
        statusItem.onOpenPanel = { [weak self] in self?.panel.show() }
        statusItem.onOpenSettings = { [weak self] in self?.settingsWindow.show() }

        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in self?.panel.toggle() }
        KeyboardShortcuts.onKeyUp(for: .clearClipboard) { [weak self] in self?.clipboard.clearIfOwned() }
        for preset in Preset.builtIns {
            guard let name = KeyboardShortcuts.Name.presetShortcuts[preset.id] else { continue }
            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                self?.model.quickCopy(preset)
                self?.statusItem.flashCopied()
            }
        }

        if !settings.hasCompletedOnboarding {
            onboarding = OnboardingWindowController(settings: settings)
            onboarding?.show()
        }
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
