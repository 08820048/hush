import AppKit
import Combine
import HushCore
import SwiftUI

/// The menu bar quick panel ("mini generator", design B): opens under the status item with a
/// password already generated; switch mode, change the size, re-roll, then copy.
@MainActor
final class QuickPanelController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 384

    private let model: AppModel
    private let panel: KeyablePanel
    private let hosting: NSHostingController<AnyView>
    private var keyMonitor: Any?
    private var changes: AnyCancellable?
    /// The status item button the panel hangs from.
    private weak var anchor: NSView?

    var onOpenMainPanel: (() -> Void)?
    var onOpenWebsiteRules: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCopied: (() -> Void)?

    init(model: AppModel, history: HistoryStore) {
        self.model = model
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        let actions = QuickPanelActions()
        hosting = NSHostingController(rootView: AnyView(
            QuickPanelView()
                .environmentObject(model)
                .environmentObject(model.clipboard)
                .environmentObject(model.presets)
                .environmentObject(actions)
        ))
        hosting.sizingOptions = []
        super.init()

        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.setAccessibilityLabel("Hush")
        panel.contentViewController = hosting

        actions.copyAndClose = { [weak self] in self?.copyAndClose() }
        actions.close = { [weak self] in self?.hide() }
        actions.openMainPanel = { [weak self] in self?.hide(); self?.onOpenMainPanel?() }
        actions.openWebsiteRules = { [weak self] in self?.hide(); self?.onOpenWebsiteRules?() }
        actions.openSettings = { [weak self] in self?.hide(); self?.onOpenSettings?() }

        // Mode switches, presets and the clipboard banner change the height; refit after SwiftUI updates.
        changes = model.objectWillChange
            .merge(with: model.clipboard.objectWillChange, model.presets.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.panel.isVisible else { return }
                self.fit()
            }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(below anchor: NSView) {
        isVisible ? hide() : show(below: anchor)
    }

    func show(below anchor: NSView) {
        self.anchor = anchor
        model.noteTargetApp()
        model.form = nil
        model.showsHistory = false
        model.regenerate()
        fit()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere else closes the panel, like a menu.
        hide()
    }

    private func copyAndClose() {
        model.copyCurrent()
        hide()
        onCopied?()
    }

    // MARK: Layout

    private func fit() {
        let size = hosting.sizeThatFits(in: CGSize(width: Self.width, height: 2_000))
        let height = size.height.rounded(.up)
        guard let anchor, let window = anchor.window else {
            panel.setContentSize(NSSize(width: Self.width, height: height))
            return
        }
        // Hang the panel 6 pt under the status item, centred on it, kept on screen.
        let buttonFrame = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? buttonFrame
        var x = buttonFrame.midX - Self.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - Self.width - 8)
        let y = buttonFrame.minY - 6 - height
        panel.setFrame(NSRect(x: x, y: y, width: Self.width, height: height), display: true)
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.panel else { return false }
                return self.handle(event)
            }
            return handled ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        switch event.keyCode {
        case 36, 76: copyAndClose() // Return, Enter
        case 53: hide() // Esc
        case 49 where !command: model.regenerate() // Space
        case 126: model.adjustPrimary(by: 1) // Up
        case 125: model.adjustPrimary(by: -1) // Down
        default:
            guard let characters = event.charactersIgnoringModifiers else { return false }
            if !command, let n = Int(characters), (1...Mode.allCases.count).contains(n) {
                model.select(Mode.allCases[n - 1])
            } else if command, characters == "c" {
                model.copyCurrent()
                onCopied?()
            } else {
                return false
            }
        }
        return true
    }
}

@MainActor
final class QuickPanelActions: ObservableObject {
    var copyAndClose: () -> Void = {}
    var close: () -> Void = {}
    var openMainPanel: () -> Void = {}
    var openWebsiteRules: () -> Void = {}
    var openSettings: () -> Void = {}
}

// MARK: - View

struct QuickPanelView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var actions: QuickPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modes
            QuickStage()
            SliderRow(
                label: model.primaryLabel,
                value: model.config.primarySize ?? 0,
                range: model.primaryRange,
                step: model.primaryStep,
                disabled: model.config.primarySize == nil
            ) { model.setPrimary($0) }
            .padding(.horizontal, 4)
            buttons
            QuickPresets()
            QuickClipboardBanner()
            footer
        }
        .padding(10)
        .frame(width: QuickPanelController.width)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedHairline(cornerRadius: Radius.lg, color: Color.black.opacity(0.14)))
        .focusEffectDisabled()
    }

    /// All five names when they fit (Chinese); otherwise only the active one is named (English).
    private var modes: some View {
        ViewThatFits(in: .horizontal) {
            modeRow(compact: false)
            modeRow(compact: true)
        }
    }

    private func modeRow(compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 0) {
            ForEach(Mode.allCases, id: \.self) { mode in
                ModeTab(mode: mode, isActive: model.mode == mode, compact: compact) { model.select(mode) }
                if !compact, mode != Mode.allCases.last { Spacer(minLength: 0) }
            }
            if compact { Spacer(minLength: 0) }
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button(action: actions.copyAndClose) {
                Text("Copy and Close  ↩").frame(maxWidth: .infinity)
            }
            .buttonStyle(HushButtonStyle(tone: .primary))
            .disabled(model.secret == nil)
            Button { model.regenerate() } label: { Text("New  ␣") }
                .buttonStyle(HushButtonStyle(tone: .secondary))
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            QuickFooterAction(icon: .open, title: String(localized: "Full Panel ⌥⌘P"), action: actions.openMainPanel)
            QuickFooterAction(icon: .gear, title: String(localized: "Settings"), action: actions.openSettings)
            #if !APP_STORE
            QuickFooterAction(icon: .globe, title: String(localized: "Updates")) {
                actions.close()
                Updates.openReleasesPage()
            }
            .help("Opens the latest release on GitHub. Hush itself never goes online.")
            #endif
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 8)
        }
    }
}

/// The password, coloured by character kind, with the strength meter underneath.
private struct QuickStage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let bits = model.config.entropyBits
        let strength = Strength(bits: bits)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if let error = model.errorMessage {
                        Text(error).font(.system(size: 13)).foregroundStyle(Palette.warn)
                    } else if model.mode == .pin {
                        Text(model.display).font(.system(size: size, design: .monospaced)).foregroundStyle(Palette.ink)
                    } else {
                        SecretText.attributed(model.display, size: size)
                    }
                }
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(SecretText.spokenDescription(model.secret?.value ?? ""))

                Button { model.regenerate() } label: {
                    GlassIcon(icon: .shuffle, size: 16)
                        .frame(width: 28, height: 28)
                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedHairline(cornerRadius: 7, color: Palette.lineStrong))
                }
                .buttonStyle(.plain)
                .help("New (Space)")
            }
            HStack(spacing: 10) {
                Text(strength.title).font(.system(size: 12, weight: .medium)).foregroundStyle(strength == .weak ? Palette.warn : Palette.ink)
                Text("\(Int(bits.rounded())) bits").font(.system(size: 12)).foregroundStyle(Palette.muted)
                Meter(strength: strength)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Long secrets (keys, long phrases) use smaller type so they stay on one or two lines.
    private var size: CGFloat {
        switch model.display.count {
        case ...20: 21
        case ...28: 18
        default: 15
        }
    }
}

/// Presets as small pills; tapping one switches the generator to it.
private struct QuickPresets: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presets: PresetStore
    @EnvironmentObject private var actions: QuickPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets").font(.system(size: 11)).foregroundStyle(Palette.faint).padding(.horizontal, 4)
            FlowLayout(spacing: 6) {
                ForEach(presets.all) { preset in
                    PresetPill(icon: preset.icon, title: preset.displayName, style: presets.matching(model.config)?.id == preset.id ? .on : .off) {
                        model.apply(preset)
                    }
                }
                PresetPill(icon: .globe, title: String(localized: "Follow a Website’s Rules…"), style: .ghost, action: actions.openWebsiteRules)
            }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Hairline(color: Palette.line) }
    }
}

private struct PresetPill: View {
    enum Style { case on, off, ghost }
    let icon: Glass
    let title: String
    let style: Style
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                GlassIcon(icon: icon, size: 15)
                Text(title).font(.system(size: 12)).lineLimit(1)
            }
            .foregroundStyle(style == .on || hovering ? Palette.ink : Palette.muted)
            .padding(.leading, 7)
            .padding(.trailing, 10)
            .frame(height: 26)
            .background {
                if style != .ghost {
                    Capsule().fill(Palette.raised)
                }
            }
            .overlay {
                switch style {
                case .on: Capsule().strokeBorder(Palette.accent, lineWidth: 1)
                case .off: Capsule().strokeBorder(hovering ? Palette.lineStrong : Palette.line, lineWidth: 1)
                case .ghost: EmptyView()
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(style == .on ? .isSelected : [])
    }
}

/// Shown only while a Hush password is on the clipboard.
private struct QuickClipboardBanner: View {
    @EnvironmentObject private var clipboard: ClipboardService

    var body: some View {
        if clipboard.heldValue != nil {
            HStack(spacing: 8) {
                GlassIcon(icon: .timer, size: 15)
                Group {
                    if let remaining = clipboard.remaining {
                        Text("Clipboard password clears in \(remaining) s")
                    } else {
                        Text("A Hush password is on the clipboard")
                    }
                }
                .foregroundStyle(Palette.accentInk)
                Spacer()
                Button("Clear Now") { clipboard.clearIfOwned() }
                    .buttonStyle(.plain)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.accentInk)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

private struct QuickFooterAction: View {
    let icon: Glass
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                GlassIcon(icon: icon, size: 15)
                Text(title).font(.system(size: 12)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(hovering ? Palette.ink : Palette.muted)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background {
                if hovering { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.sunken) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Lays children out left to right, wrapping to a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !current.indices.isEmpty, current.width + spacing + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
