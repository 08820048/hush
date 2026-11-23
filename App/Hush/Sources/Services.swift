import AppKit
import ApplicationServices
import HushCore
import SwiftUI

// MARK: - Clipboard

/// Copies secrets so clipboard managers skip them, and clears them again after a delay.
@MainActor
final class ClipboardService: ObservableObject {
    /// Seconds until the clipboard is cleared, while Hush's secret is still on it.
    @Published private(set) var remaining: Int?
    /// Total seconds for the current countdown (for progress bars).
    @Published private(set) var total: Int = 0
    /// The secret currently held on the clipboard, if it is still ours.
    @Published private(set) var heldValue: String?

    var onStateChange: (() -> Void)?

    private var ownedChangeCount: Int?
    private var countdown: Task<Void, Never>?

    /// Markers from nspasteboard.org that clipboard managers honour.
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    func copy(_ value: String, conceal: Bool, clearAfter seconds: Int) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(value, forType: .string)
        if conceal {
            item.setString("", forType: Self.concealedType)
            item.setString("", forType: Self.transientType)
        }
        pasteboard.writeObjects([item])
        ownedChangeCount = pasteboard.changeCount
        heldValue = value
        startCountdown(seconds)
    }

    /// Clears the clipboard now, but only if it still holds Hush's secret.
    func clearIfOwned() {
        let pasteboard = NSPasteboard.general
        if let owned = ownedChangeCount, pasteboard.changeCount == owned {
            pasteboard.clearContents()
        }
        reset()
    }

    var isHolding: Bool {
        guard let owned = ownedChangeCount else { return false }
        return NSPasteboard.general.changeCount == owned
    }

    private func startCountdown(_ seconds: Int) {
        countdown?.cancel()
        total = seconds
        remaining = seconds > 0 ? seconds : nil
        onStateChange?()
        guard seconds > 0 else { return }
        countdown = Task { [weak self] in
            var left = seconds
            while left > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                // The user copied something else: stop, never touch their content.
                guard self.isHolding else {
                    self.reset()
                    return
                }
                left -= 1
                self.remaining = left
            }
            self?.clearIfOwned()
        }
    }

    private func reset() {
        countdown?.cancel()
        countdown = nil
        ownedChangeCount = nil
        heldValue = nil
        remaining = nil
        onStateChange?()
    }
}

// MARK: - Direct paste

/// Sends ⌘V to the app that was frontmost when the panel opened. Needs Accessibility permission.
enum PasteService {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to Privacy & Security › Accessibility.
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func pasteIntoFrontApp() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

// MARK: - Ephemeral history

/// The last few secrets, in memory only. Never written to disk; wiped after a few minutes,
/// on screen lock, on sleep and on quit.
@MainActor
final class HistoryStore: ObservableObject {
    struct Entry: Identifiable, Hashable {
        let id = UUID()
        let value: String
        let mode: Mode
        let date: Date
    }

    static let capacity = 10
    static let lifetime: TimeInterval = 5 * 60

    @Published private(set) var entries: [Entry] = []
    private var sweeper: Task<Void, Never>?

    init() {
        let wipe: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.clear() }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main, using: wipe)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: wipe)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: wipe)
    }

    func add(_ value: String, mode: Mode) {
        entries.removeAll { $0.value == value }
        entries.insert(Entry(value: value, mode: mode, date: .now), at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
        scheduleSweep()
    }

    func clear() {
        entries.removeAll()
        sweeper?.cancel()
    }

    private func scheduleSweep() {
        sweeper?.cancel()
        sweeper = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                let cutoff = Date.now.addingTimeInterval(-Self.lifetime)
                self.entries.removeAll { $0.date < cutoff }
                if self.entries.isEmpty { return }
            }
        }
    }
}

// MARK: - Small toast

/// A quiet, non-activating HUD for one-line confirmations.
@MainActor
final class Toast {
    static let shared = Toast()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, icon: Glass = .copy) {
        let view = HStack(spacing: 10) {
            GlassIcon(icon: icon, size: 20)
            Text(message).font(.system(size: 13)).foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedHairline(cornerRadius: 12, color: Palette.lineStrong))
        .padding(20)

        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .statusBar
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            return p
        }()
        self.panel = panel
        panel.contentView = hosting
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 12, width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak panel] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, let panel else { return }
            // Fade with the animator's default 0.25 s, then remove the window once it is invisible.
            panel.animator().alphaValue = 0
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }
}
