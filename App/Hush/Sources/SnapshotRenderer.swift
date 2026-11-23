#if DEBUG
import AppKit
import HushCore
import SwiftUI

/// Debug-only: `Hush --render-snapshots` renders the main screens offscreen to PNGs in the
/// sandbox's temporary directory, so UI can be checked against the design without screen
/// recording permission. Not compiled into release builds.
@MainActor
enum SnapshotRenderer {
    static func run() {
        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hush-snapshots", isDirectory: true)
        try? FileManager.default.removeItem(at: out)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let defaults = UserDefaults(suiteName: "hush.snapshots")!
        defaults.removePersistentDomain(forName: "hush.snapshots")
        let settings = AppSettings(defaults: defaults)
        settings.animationsEnabled = false
        let history = HistoryStore()
        let presets = PresetStore(defaults: defaults)
        presets.add(name: "Team VPN", config: .random(RandomOptions(length: 24, symbolSet: CharacterPools.compatibleSymbols)))
        let model = AppModel(settings: settings, clipboard: ClipboardService(), history: history, presets: presets)
        let actions = PanelActions()

        for (themeName, appearance) in [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)] {
            for mode in Mode.allCases {
                model.select(mode)
                model.regenerate(animated: false)
                let view = PanelView().environmentObject(model).environmentObject(actions).environmentObject(history).environmentObject(presets)
                save(view, appearance: appearance, to: out.appendingPathComponent("panel-\(mode.rawValue)-\(themeName).png"))
            }
            for mode in [Mode.random, .passphrase, .key] {
                model.select(mode)
                model.regenerate(animated: false)
                if mode == .passphrase { model.clipboard.previewHolding("Velvet-Otter-Ample-Crane-Harbor7", remaining: 18, of: 30) }
                let quick = QuickPanelView()
                    .environmentObject(model).environmentObject(model.clipboard).environmentObject(presets).environmentObject(QuickPanelActions())
                save(quick, appearance: appearance, to: out.appendingPathComponent("quick-\(mode.rawValue)-\(themeName).png"))
            }
            model.clipboard.clearIfOwned()
            model.select(.random)
            model.beginSavingPreset()
            save(PanelView().environmentObject(model).environmentObject(actions).environmentObject(history).environmentObject(presets),
                 appearance: appearance, to: out.appendingPathComponent("panel-save-preset-\(themeName).png"))
            model.applyWebsite("https://account.xiaomi.com/login")
            save(PanelView().environmentObject(model).environmentObject(actions).environmentObject(history).environmentObject(presets),
                 appearance: appearance, to: out.appendingPathComponent("panel-site-applied-\(themeName).png"))
            model.form = .website
            save(PanelView().environmentObject(model).environmentObject(actions).environmentObject(history).environmentObject(presets),
                 appearance: appearance, to: out.appendingPathComponent("panel-website-\(themeName).png"))
            model.form = nil
            save(OnboardingView(done: {}).environmentObject(settings), appearance: appearance, to: out.appendingPathComponent("onboarding-\(themeName).png"))
        }
        for (themeName, appearance) in [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)] {
            NSApp.appearance = appearance
            for page in SettingsPage.allCases {
                let controller = SettingsWindowController(settings: settings, presets: presets)
                controller.page = page
                controller.show()
                if let window = controller.window {
                    capture(window, to: out.appendingPathComponent("settings-\(page.rawValue)-\(themeName).png"))
                    window.close()
                }
            }
        }
        NSApp.appearance = nil
        print("SNAPSHOTS:\(out.path)")
        fflush(stdout)
        exit(0)
    }

    /// Captures a real window including its title bar, so window chrome issues show up too.
    private static func capture(_ window: NSWindow, to url: URL) {
        guard let frameView = window.contentView?.superview else { return }
        frameView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        frameView.display()
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func save<V: View>(_ view: V, appearance: NSAppearance, to url: URL) {
        let hosting = NSHostingView(rootView: view.padding(24).background(Palette.ground))
        hosting.appearance = appearance
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        hosting.display()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
