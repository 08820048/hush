import AppKit
import Combine
import HushCore
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.p, modifiers: [.option, .command]))
    static let clearClipboard = Self("clearClipboard")

    /// Global "generate & copy" shortcuts for presets, matching the menu in design 04.
    static let presetShortcuts: [String: KeyboardShortcuts.Name] = [
        "default": Self("preset.default", default: .init(.one, modifiers: [.control, .option])),
        "wifi": Self("preset.wifi", default: .init(.two, modifiers: [.control, .option])),
        "pin6": Self("preset.pin6", default: .init(.three, modifiers: [.control, .option])),
        "devkey": Self("preset.devkey", default: .init(.four, modifiers: [.control, .option])),
        "compatible": Self("preset.compatible"),
        "memorable": Self("preset.memorable"),
    ]
}

/// The three fading dots. Monochrome template images, so macOS tints them for light/dark menu bars.
enum MenuBarIcon {
    enum State { case rest, copied, holding }

    static func image(_ state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
            let y: CGFloat = 8
            switch state {
            case .copied:
                for x in [5.5, 11.0, 16.5] { dot(x: x, y: y, d: 4.5, alpha: 1) }
            case .rest, .holding:
                dot(x: 5.5, y: y, d: 5, alpha: 1)
                dot(x: 11.5, y: y, d: 4, alpha: 0.55)
                if state == .holding {
                    let r = NSRect(x: 16.5 - 1.75, y: y - 1.75, width: 3.5, height: 3.5)
                    NSColor.black.setStroke()
                    let path = NSBezierPath(ovalIn: r)
                    path.lineWidth = 1
                    path.stroke()
                } else {
                    dot(x: 16.5, y: y, d: 3, alpha: 0.25)
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Hush"
        return image
    }

    private static func dot(x: CGFloat, y: CGFloat, d: CGFloat, alpha: CGFloat) {
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - d / 2, y: y - d / 2, width: d, height: d)).fill()
    }
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var flashTask: Task<Void, Never>?
    private var isFlashing = false
    private var cancellables: Set<AnyCancellable> = []

    var onOpenPanel: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        super.init()
        menu.delegate = self
        if let button = item.button {
            button.image = MenuBarIcon.image(.rest)
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = String(localized: "Hush · Click to generate and copy, right-click for the menu")
        }
        model.clipboard.$heldValue
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            item.menu = menu
            item.button?.performClick(nil)
        } else {
            model.quickCopy(model.settings.menuBarPreset)
            flashCopied()
        }
    }

    func flashCopied() {
        flashTask?.cancel()
        isFlashing = true
        item.button?.image = MenuBarIcon.image(.copied)
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            self.isFlashing = false
            self.refreshIcon()
        }
    }

    private func refreshIcon() {
        guard !isFlashing else { return }
        item.button?.image = MenuBarIcon.image(model.clipboard.heldValue != nil ? .holding : .rest)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if model.clipboard.heldValue != nil {
            let header = NSMenuItem()
            let hosting = NSHostingView(rootView: MenuHeader().environmentObject(model.clipboard))
            hosting.frame.size = hosting.fittingSize
            header.view = hosting
            menu.addItem(header)
            menu.addItem(.separator())
        }

        menu.addItem(entry(String(localized: "Open Hush"), icon: .open, shortcut: .togglePanel) { [weak self] in self?.onOpenPanel?() })
        menu.addItem(entry(String(localized: "Generate and Copy"), icon: .copy, shortcut: nil) { [weak self] in
            guard let self else { return }
            self.model.quickCopy(self.model.settings.menuBarPreset)
            self.flashCopied()
        })
        menu.addItem(.separator())

        let title = NSMenuItem(title: String(localized: "Presets"), action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        for preset in Preset.builtIns {
            menu.addItem(entry(preset.displayName, icon: icon(for: preset), shortcut: KeyboardShortcuts.Name.presetShortcuts[preset.id]) { [weak self] in
                self?.model.quickCopy(preset)
                self?.flashCopied()
            })
        }
        menu.addItem(.separator())
        let clear = entry(String(localized: "Clear Clipboard Now"), icon: .notrack, shortcut: .clearClipboard) { [weak self] in self?.model.clipboard.clearIfOwned() }
        clear.isEnabled = model.clipboard.heldValue != nil
        menu.addItem(clear)
        menu.addItem(entry(String(localized: "Settings…"), icon: .gear, shortcut: nil) { [weak self] in self?.onOpenSettings?() })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit Hush"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func menuDidClose(_ menu: NSMenu) {
        item.menu = nil
    }

    private func entry(_ title: String, icon: Glass, shortcut: KeyboardShortcuts.Name?, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        item.image = icon.menuImage()
        if let shortcut { item.setShortcut(for: shortcut) }
        return item
    }

    private func icon(for preset: Preset) -> Glass {
        switch preset.id {
        case "default": .shield
        case "wifi": .broadcast
        case "pin6": .keypad
        case "devkey": .braces
        case "memorable": .lines
        default: preset.config.mode.icon
        }
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func fire() { handler() }
}

/// Top of the menu: the held secret, masked, with the clear countdown.
private struct MenuHeader: View {
    @EnvironmentObject private var clipboard: ClipboardService
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Just generated · Copied").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                GlassIcon(icon: .eye, size: 16)
                    .onHover { revealed = $0 }
                    .help("Hover to reveal")
            }
            Text(revealed ? (clipboard.heldValue ?? "") : masked(clipboard.heldValue ?? ""))
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            if let remaining = clipboard.remaining, clipboard.total > 0 {
                HStack(spacing: 8) {
                    GlassIcon(icon: .timer, size: 16)
                    ProgressView(value: Double(remaining), total: Double(clipboard.total))
                        .progressViewStyle(.linear)
                        .tint(Palette.accent)
                    Text("\(remaining)s").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                }
            }
        }
        .padding(12)
        .frame(width: 276)
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func masked(_ value: String) -> String {
        guard value.count > 8 else { return String(repeating: "•", count: value.count) }
        return String(value.prefix(4)) + String(repeating: "•", count: 12) + String(value.suffix(4))
    }
}
