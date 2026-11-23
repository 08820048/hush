import HushCore
import KeyboardShortcuts
import SwiftUI

@MainActor
final class SettingsWindowController {
    private(set) var window: NSWindow?
    private var hosting: NSHostingController<AnyView>?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// The page a newly created window opens on (used by the snapshot renderer).
    var page: SettingsPage = .general

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        fitToPage()
        window.presentOnMouseScreen()
        // Nothing should look focused when the window opens (no focus ring on the first tab,
        // and the shortcut recorders must not start recording on their own).
        window.makeFirstResponder(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = String(localized: "Hush Settings")
        window.backgroundColor = NSColor(Palette.surface)

        let hosting = NSHostingController(rootView: AnyView(SettingsView(page: page) { [weak self] in
            // Measure after SwiftUI has applied the new page.
            DispatchQueue.main.async { self?.fitToPage() }
        }.environmentObject(settings)))
        // The window size is driven by `fitToPage()`; the hosting view must not impose its own.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: SettingsView.width, height: 460))
        self.hosting = hosting
        return window
    }

    /// Grows or shrinks the window to fit the current page, keeping its top edge in place.
    private func fitToPage() {
        guard let window, let hosting else { return }
        let height = hosting.sizeThatFits(in: CGSize(width: SettingsView.width, height: 10_000)).height
        let limit = (window.screen?.visibleFrame.height ?? 900) - 40
        let target = min(height.rounded(.up), limit)
        var frame = window.frame
        guard abs(frame.height - target) > 0.5 else { return }
        frame.origin.y += frame.height - target
        frame.size.height = target
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, privacy, presets, appearance, advanced, developer
    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .privacy: String(localized: "Privacy")
        case .presets: String(localized: "Presets")
        case .appearance: String(localized: "Appearance")
        case .advanced: String(localized: "Advanced")
        case .developer: String(localized: "Developer")
        }
    }

    var icon: Glass {
        switch self {
        case .general: .gear
        case .privacy: .shield
        case .presets: .tag
        case .appearance: .eye
        case .advanced: .sliders
        case .developer: .braces
        }
    }
}

/// One continuous surface: the tab row sits in the title bar next to the window controls,
/// the page flows directly underneath, and the window is exactly as tall as the page.
struct SettingsView: View {
    static let width: CGFloat = 660
    private let onPageChange: @MainActor () -> Void

    @State private var page: SettingsPage

    init(page: SettingsPage = .general, onPageChange: @escaping @MainActor () -> Void = {}) {
        _page = State(initialValue: page)
        self.onPageChange = onPageChange
    }

    var body: some View {
        VStack(spacing: 0) {
            tabs
            VStack(alignment: .leading, spacing: 14) {
                switch page {
                case .general: GeneralPage()
                case .privacy: PrivacyPage()
                case .presets: PresetsPage()
                case .appearance: AppearancePage()
                case .advanced: AdvancedPage()
                case .developer: DeveloperPage()
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 6)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: page) { onPageChange() }
        .frame(width: Self.width)
        .background(Palette.surface)
        .ignoresSafeArea()
        .focusEffectDisabled()
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(SettingsPage.allCases) { item in
                Button { page = item } label: {
                    VStack(spacing: 4) {
                        GlassIcon(icon: item.icon, size: 26, muted: page != item)
                        Text(item.title)
                            .font(.system(size: 11, weight: page == item ? .medium : .regular))
                            .foregroundStyle(page == item ? Palette.ink : Palette.muted)
                    }
                    .frame(width: 76, height: 56)
                    .background {
                        if page == item {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Palette.raised)
                                .overlay(RoundedHairline(cornerRadius: 9, color: Palette.line))
                                .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityAddTraits(page == item ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }
}

// MARK: Pages

private struct GeneralPage: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsGroup {
            SettingRow(icon: .open, title: String(localized: "Open Hush"), detail: String(localized: "Brings up the panel in any app")) {
                KeyboardShortcuts.Recorder(for: .togglePanel)
            }
            Divider().padding(.leading, 42)
            SettingRow(icon: .flag, title: String(localized: "Launch at login"), detail: String(localized: "Lives in the menu bar, never in the Dock")) {
                Toggle("", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch).tint(Palette.accent).labelsHidden()
            }
            Divider().padding(.leading, 42)
            SettingRow(icon: .copy, title: String(localized: "Click the menu bar icon"), detail: String(localized: "Generates and copies with this preset")) {
                Picker("", selection: $settings.menuBarPresetID) {
                    ForEach(Preset.builtIns) { Text($0.displayName).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 150)
            }
        }
        AboutBlock()
    }
}

private struct PrivacyPage: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                GlassIcon(icon: .timer, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Clear the clipboard after copying").font(.system(size: 13))
                    Text("Only if it still holds the password, so nothing you copy later is lost").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
            }
            Picker("", selection: $settings.clearAfterSeconds) {
                ForEach(AppSettings.clearIntervals, id: \.self) { s in
                    Text(s == 0 ? String(localized: "Never") : String(localized: "\(s) s")).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.leading, 42)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedHairline(cornerRadius: Radius.md, color: Palette.line))

        SettingsGroup {
            SettingRow(icon: .notrack, title: String(localized: "Hide from clipboard managers"), detail: String(localized: "Marked as concealed, so Maccy, Paste and Raycast skip it")) {
                Toggle("", isOn: $settings.concealFromClipboardManagers).toggleStyle(.switch).tint(Palette.accent).labelsHidden()
            }
            Divider().padding(.leading, 42)
            SettingRow(icon: .eye, title: String(localized: "Temporary history"), detail: String(localized: "Memory only, up to 10 items, wiped after 5 minutes or on lock")) {
                Toggle("", isOn: $settings.historyEnabled).toggleStyle(.switch).tint(Palette.accent).labelsHidden()
            }
            Divider().padding(.leading, 42)
            SettingRow(icon: .copy, title: String(localized: "Show a notice after copying"), detail: String(localized: "When off, only the menu bar icon changes")) {
                Toggle("", isOn: $settings.showCopyToast).toggleStyle(.switch).tint(Palette.accent).labelsHidden()
            }
        }

        HStack(spacing: 14) {
            GlassIcon(icon: .broadcast, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("Network access: none").font(.system(size: 13))
                Text("The sandbox has no network entitlement. Check Hush.entitlements in the repository.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        .padding(16)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

private struct PresetsPage: View {
    var body: some View {
        SettingsGroup {
            ForEach(Array(Preset.builtIns.enumerated()), id: \.element.id) { index, preset in
                if index > 0 { Divider().padding(.leading, 42) }
                SettingRow(icon: preset.config.mode.icon, title: preset.displayName, detail: "\(preset.config.mode.title) · \(Int(preset.config.entropyBits.rounded())) bits") {
                    if let name = KeyboardShortcuts.Name.presetShortcuts[preset.id] {
                        KeyboardShortcuts.Recorder(for: name)
                    }
                }
            }
        }
        Text("Press a preset’s shortcut anywhere to generate and copy it. In the panel, ⌘1–⌘6 switch presets.").font(.system(size: 12)).foregroundStyle(Palette.muted)
    }
}

private struct AppearancePage: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsGroup {
            SettingRow(icon: .eye, title: String(localized: "Appearance"), detail: String(localized: "Porcelain light / graphite dark")) {
                Picker("", selection: $settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            Divider().padding(.leading, 42)
            SettingRow(icon: .shuffle, title: String(localized: "Reveal animation"), detail: String(localized: "The password briefly scrolls before settling. Off when Reduce Motion is on.")) {
                Toggle("", isOn: $settings.animationsEnabled).toggleStyle(.switch).tint(Palette.accent).labelsHidden()
            }
        }
    }
}

private struct AdvancedPage: View {
    @State private var trusted = PasteService.isTrusted

    var body: some View {
        SettingsGroup {
            SettingRow(icon: .open, title: String(localized: "Paste directly (⌘↩)"), detail: trusted ? String(localized: "Accessibility access granted") : String(localized: "Allow Hush in Privacy & Security › Accessibility. Until then, Hush only copies.")) {
                if trusted {
                    Text("Allowed").font(.system(size: 12)).foregroundStyle(Palette.accentInk)
                } else {
                    Button("Allow…") {
                        PasteService.requestTrust()
                        PasteService.openAccessibilitySettings()
                    }
                    .buttonStyle(HushButtonStyle(tone: .secondary))
                }
            }
            Divider().padding(.leading, 42)
            SettingRow(icon: .notrack, title: String(localized: "Clear clipboard now"), detail: String(localized: "Global shortcut. Only clears passwords Hush put there.")) {
                KeyboardShortcuts.Recorder(for: .clearClipboard)
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in trusted = PasteService.isTrusted }
    }
}

private struct DeveloperPage: View {
    var body: some View {
        SettingsGroup {
            SettingRow(icon: .braces, title: String(localized: "Command-line tool: hush"), detail: String(localized: "Shares the same generator core as the app")) {
                EmptyView()
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            ForEach([
                "hush                       # strong 20-character password",
                "hush -l 32 --no-symbols",
                "hush phrase -w 6 -s .",
                "hush pin 6",
                "hush key --bytes 32 -f base64url",
                "hush -p wifi --json",
            ], id: \.self) { line in
                Text(line).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.ink)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        Text("To install, run swift build -c release in the repository root, then put .build/release/hush on your PATH.").font(.system(size: 12)).foregroundStyle(Palette.muted)
    }
}

private struct AboutBlock: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hush \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.system(size: 13, weight: .medium))
                Text("MIT licensed · Passphrase word list by the EFF (CC BY 3.0)").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.top, 8)
    }
}
