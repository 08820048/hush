import HushCore
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController {
    private(set) var window: NSWindow?
    private let settings: AppSettings
    private let presets: PresetStore

    init(settings: AppSettings, presets: PresetStore) {
        self.settings = settings
        self.presets = presets
    }

    /// The page a newly created window opens on (used by the snapshot renderer).
    var page: SettingsPage = .general

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.presentOnMouseScreen()
        // Nothing should look focused when the window opens (no focus ring on the sidebar,
        // and the shortcut recorders must not start recording on their own).
        window.makeFirstResponder(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: contentHeight()),
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

        let hosting = NSHostingController(rootView: SettingsView(page: page).environmentObject(settings).environmentObject(presets))
        // The window keeps the size set here; the hosting view must not impose its own.
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: SettingsView.width, height: contentHeight()))
        return window
    }

    /// Tall enough for the tallest page, so switching pages never resizes the window.
    private func contentHeight() -> CGFloat {
        let width = SettingsView.contentWidth
        let tallest = SettingsPage.allCases.map { page in
            NSHostingController(rootView: SettingsPageContent(page: page).environmentObject(settings).environmentObject(presets).frame(width: width))
                .sizeThatFits(in: CGSize(width: width, height: 10_000)).height
        }.max() ?? 480
        // Long custom preset lists scroll instead of growing the window past this.
        return min(tallest, 640).rounded(.up)
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

/// One continuous surface: a sidebar on the same background as the page (no tinted column,
/// no divider), with the selected page lifted as a raised tile. The window has a fixed height
/// that fits the tallest page, so switching pages never resizes it.
struct SettingsView: View {
    static let width: CGFloat = 760
    static let sidebarWidth: CGFloat = 188
    static var contentWidth: CGFloat { width - sidebarWidth }

    @State private var page: SettingsPage

    init(page: SettingsPage = .general) {
        _page = State(initialValue: page)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            ScrollView {
                SettingsPageContent(page: page)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Palette.surface)
        .ignoresSafeArea()
        .focusEffectDisabled()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPage.allCases) { item in
                Button { page = item } label: {
                    HStack(spacing: 10) {
                        GlassIcon(icon: item.icon, size: 20, muted: page != item)
                        Text(item.title)
                            .font(.system(size: 13, weight: page == item ? .medium : .regular))
                            .foregroundStyle(page == item ? Palette.ink : Palette.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background {
                        if page == item {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Palette.raised)
                                .overlay(RoundedHairline(cornerRadius: 8, color: Palette.line))
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
        .padding(.top, 52) // clears the window controls
        .padding(.horizontal, 14)
        .frame(width: Self.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The right-hand column: page title and its settings.
struct SettingsPageContent: View {
    let page: SettingsPage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(page.title)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 2)
            switch page {
            case .general: GeneralPage()
            case .privacy: PrivacyPage()
            case .presets: PresetsPage()
            case .appearance: AppearancePage()
            case .advanced: AdvancedPage()
            case .developer: DeveloperPage()
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 28)
        .padding(.top, 46)
        .padding(.bottom, 28)
    }
}

// MARK: Pages

private struct GeneralPage: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var presets: PresetStore

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
            SettingRow(icon: .copy, title: String(localized: "Click the menu bar icon"), detail: String(localized: "Generates and copies with this preset. Right-click opens the quick panel.")) {
                Picker("", selection: $settings.menuBarPresetID) {
                    ForEach(presets.all) { Text($0.displayName).tag($0.id) }
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
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var presets: PresetStore
    @State private var renaming: Preset?
    @State private var newName = ""
    @State private var fileMessage: String?

    var body: some View {
        SettingsGroup {
            ForEach(Array(Preset.builtIns.enumerated()), id: \.element.id) { index, preset in
                if index > 0 { Divider().padding(.leading, 42) }
                row(preset)
            }
        }

        HStack(spacing: 8) {
            Text("My presets").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
            Spacer()
            Button("Import…", action: importPresets)
                .buttonStyle(HushButtonStyle(tone: .ghost))
            Button("Export…", action: exportPresets)
                .buttonStyle(HushButtonStyle(tone: .ghost))
                .disabled(presets.custom.isEmpty)
        }
        .padding(.top, 6)
        if presets.custom.isEmpty {
            HStack(spacing: 14) {
                GlassIcon(icon: .tag, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("No presets of your own yet").font(.system(size: 13)).foregroundStyle(Palette.ink)
                    Text("In the panel, set things up the way you like, then choose Save as Preset… from the preset menu (⌘S).")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedHairline(cornerRadius: Radius.md, color: Palette.line))
        } else {
            SettingsGroup {
                ForEach(Array(presets.custom.enumerated()), id: \.element.id) { index, preset in
                    if index > 0 { Divider().padding(.leading, 42) }
                    row(preset)
                }
            }
        }

        Text("Press a preset’s shortcut anywhere to generate and copy it. In the panel, ⌘1–⌘9 switch presets.")
            .font(.system(size: 12)).foregroundStyle(Palette.muted)
            .alert("Rename Preset", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if let renaming { presets.rename(renaming.id, to: newName) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .alert(fileMessage ?? "", isPresented: Binding(get: { fileMessage != nil }, set: { if !$0 { fileMessage = nil } })) {
                Button("OK") { fileMessage = nil }
            }
    }

    // MARK: Import and export (only the file the user picks is accessible to the sandbox)

    private func exportPresets() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(localized: "Hush Presets") + ".json"
        panel.message = String(localized: "Presets contain settings only, never passwords.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try presets.exportData().write(to: url, options: .atomic)
        } catch {
            fileMessage = String(localized: "Couldn’t export: \(error.localizedDescription)")
        }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try presets.importData(Data(contentsOf: url))
            fileMessage = result.skipped == 0
                ? String(localized: "Imported \(result.added) presets.")
                : String(localized: "Imported \(result.added) presets, skipped \(result.skipped) already here.")
        } catch let error as PresetFile.ReadError {
            fileMessage = String(localized: "Couldn’t import: \(error.description)")
        } catch {
            fileMessage = String(localized: "Couldn’t import: \(error.localizedDescription)")
        }
    }

    private func row(_ preset: Preset) -> some View {
        SettingRow(icon: preset.icon, title: preset.displayName, detail: "\(preset.config.mode.title) · \(Int(preset.config.entropyBits.rounded())) bits") {
            HStack(spacing: 8) {
                KeyboardShortcuts.Recorder(for: .preset(preset.id))
                if !preset.isBuiltIn { actions(for: preset) }
            }
        }
    }

    private func actions(for preset: Preset) -> some View {
        Menu {
            Button("Rename…") {
                newName = preset.name
                renaming = preset
            }
            Button("Move Up") { presets.move(preset.id, by: -1) }.disabled(!presets.canMove(preset.id, by: -1))
            Button("Move Down") { presets.move(preset.id, by: 1) }.disabled(!presets.canMove(preset.id, by: 1))
            Divider()
            Button("Delete", role: .destructive) {
                if settings.menuBarPresetID == preset.id { settings.menuBarPresetID = Preset.builtIns[0].id }
                presets.delete(preset.id)
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
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
    #if !APP_STORE
    @State private var trusted = PasteService.isTrusted
    #endif

    var body: some View {
        SettingsGroup {
            #if !APP_STORE
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
            #endif
            SettingRow(icon: .notrack, title: String(localized: "Clear clipboard now"), detail: String(localized: "Global shortcut. Only clears passwords Hush put there.")) {
                KeyboardShortcuts.Recorder(for: .clearClipboard)
            }
        }
        #if !APP_STORE
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in trusted = PasteService.isTrusted }
        #endif
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hush \(Updates.currentVersion)").font(.system(size: 13, weight: .medium))
                    Text("Open source (GPL-3.0) · EFF word list (CC BY 3.0)").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                #if !APP_STORE
                Button("Check for Updates…") { Updates.openReleasesPage() }
                    .buttonStyle(HushButtonStyle(tone: .secondary))
                #endif
            }
            Text(updateNote)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var updateNote: LocalizedStringKey {
        #if APP_STORE
        "Updates arrive through the Mac App Store. Hush itself never goes online."
        #else
        "Hush never goes online, so it doesn’t check for updates by itself. The button opens the latest release on GitHub. If you installed with Homebrew, run brew upgrade --cask hush."
        #endif
    }
}
