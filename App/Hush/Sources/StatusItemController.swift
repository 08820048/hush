import AppKit
import Combine
import HushCore
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.p, modifiers: [.option, .command]))
    static let clearClipboard = Self("clearClipboard")

    /// Global "generate & copy" shortcut for a preset (built-in or custom).
    /// Four built-ins come with defaults, matching the menu in design 04.
    static func preset(_ id: String) -> Self {
        let defaults: [String: KeyboardShortcuts.Shortcut] = [
            "default": .init(.one, modifiers: [.control, .option]),
            "wifi": .init(.two, modifiers: [.control, .option]),
            "pin6": .init(.three, modifiers: [.control, .option]),
            "devkey": .init(.four, modifiers: [.control, .option]),
        ]
        return Self("preset.\(id)", default: defaults[id])
    }
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
final class StatusItemController: NSObject {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let quickPanel: QuickPanelController
    private var flashTask: Task<Void, Never>?
    private var isFlashing = false
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel, quickPanel: QuickPanelController) {
        self.model = model
        self.quickPanel = quickPanel
        super.init()
        if let button = item.button {
            button.image = MenuBarIcon.image(.rest)
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = String(localized: "Hush · Click to generate and copy, right-click for the quick panel")
        }
        model.clipboard.$heldValue
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            quickPanel.toggle(below: sender)
        } else {
            model.quickCopy(model.menuBarPreset)
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
}
