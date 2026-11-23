import AppKit
import Combine
import HushCore
import SwiftUI

/// A panel that takes keyboard focus without activating Hush, so the app the user was
/// typing in stays frontmost and can receive ⌘↩ paste.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let actions = PanelActions()
    private let panel: KeyablePanel
    private let hosting: NSHostingController<AnyView>
    private var contentChanges: AnyCancellable?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollAccumulator: CGFloat = 0

    var onShowLargeType: ((LargeTypeController.Page) -> Void)?
    var onShowSettings: (() -> Void)?

    init(model: AppModel, history: HistoryStore) {
        self.model = model
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelView.width, height: 420),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        let root = PanelView()
            .environmentObject(model)
            .environmentObject(actions)
            .environmentObject(history)
        hosting = NSHostingController(rootView: AnyView(root))
        // The panel's size is set by `fit()`, never by the hosting view itself.
        hosting.sizingOptions = []
        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.setAccessibilityLabel("Hush")

        panel.contentViewController = hosting

        // History, errors and mode switches change the panel's height; refit after SwiftUI updates.
        contentChanges = model.objectWillChange.merge(with: history.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.panel.isVisible else { return }
                self.fit()
            }

        actions.copyAndClose = { [weak self] in self?.copyAndClose() }
        actions.paste = { [weak self] in self?.pasteIntoTarget() }
        actions.close = { [weak self] in self?.hide() }
        actions.showLargeType = { [weak self] in self?.openLargeType(.text) }
        actions.showQR = { [weak self] in self?.openLargeType(.qr) }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        model.noteTargetApp()
        model.showsHistory = false
        model.isRevealed = true
        model.regenerate()
        position()
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func hide() {
        removeMonitors()
        panel.orderOut(nil)
    }

    // MARK: Actions

    private func copyAndClose() {
        model.copyCurrent()
        hide()
    }

    private func pasteIntoTarget() {
        model.copyCurrent()
        hide()
        guard PasteService.isTrusted else {
            PasteService.requestTrust()
            Toast.shared.show(String(localized: "Copied. To paste directly, allow Hush in Accessibility settings."), icon: .shield)
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            PasteService.pasteIntoFrontApp()
        }
    }

    private func openLargeType(_ page: LargeTypeController.Page) {
        hide()
        onShowLargeType?(page)
    }

    // MARK: Layout

    private var contentSize: NSSize {
        let size = hosting.sizeThatFits(in: CGSize(width: PanelView.width, height: 2_000))
        return NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let size = contentSize
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - visible.height * 0.16)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Resizes the open panel to its content, keeping the top edge where it is.
    private func fit() {
        let size = contentSize
        var frame = panel.frame
        guard abs(frame.height - size.height) > 0.5 || abs(frame.width - size.width) > 0.5 else { return }
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere else dismisses the panel.
        hide()
    }

    // MARK: Keyboard

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.panel else { return false }
                return self.handle(event)
            }
            return handled ? nil : event
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.panel, !self.model.showsHistory else { return false }
                self.scrollAccumulator += event.scrollingDeltaY
                let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 14 : 1
                if abs(self.scrollAccumulator) >= threshold {
                    self.model.adjustPrimary(by: self.scrollAccumulator > 0 ? 1 : -1)
                    self.scrollAccumulator = 0
                }
                return true
            }
            return handled ? nil : event
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        keyMonitor = nil
        scrollMonitor = nil
    }

    /// Returns true when the key was handled.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)

        switch event.keyCode {
        case 36, 76: // Return, Enter
            command ? pasteIntoTarget() : copyAndClose()
        case 53: // Esc
            if model.showsHistory { model.showsHistory = false } else { hide() }
        case 49 where !command: // Space
            model.regenerate()
        case 126: // Up
            model.adjustPrimary(by: shift ? 4 : 1)
        case 125: // Down
            model.adjustPrimary(by: shift ? -4 : -1)
        default:
            guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
            if command {
                switch characters {
                case "c": model.copyCurrent()
                case "r": model.regenerate()
                case "l": openLargeType(.text)
                case "k": openLargeType(.qr)
                case "y": model.showsHistory.toggle()
                case ",": hide(); onShowSettings?()
                case "w": hide()
                default:
                    if let n = Int(characters), (1...Preset.builtIns.count).contains(n) {
                        model.apply(Preset.builtIns[n - 1])
                    } else {
                        return false
                    }
                }
            } else if let n = Int(characters), (1...Mode.allCases.count).contains(n) {
                model.select(Mode.allCases[n - 1])
            } else {
                return false
            }
        }
        return true
    }
}
