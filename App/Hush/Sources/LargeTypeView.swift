import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import HushCore
import SwiftUI

/// Full-screen "large type" and QR code views (⌘L / ⌘K), matching design 05.
@MainActor
final class LargeTypeController: NSObject, NSWindowDelegate {
    enum Page { case text, qr }

    final class State: ObservableObject {
        @Published var page: Page = .text
        @Published var value = ""
        @Published var ssid = ""
    }

    private let state = State()
    private var window: KeyablePanel?
    private var monitor: Any?

    func show(_ value: String, page: Page) {
        state.value = value
        state.page = page
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]

        let window = self.window ?? {
            let w = KeyablePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            w.level = .modalPanel
            w.isOpaque = false
            w.backgroundColor = .clear
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            w.delegate = self
            w.contentView = NSHostingView(rootView: LargeTypeView(close: { [weak self] in self?.hide() }).environmentObject(state))
            return w
        }()
        self.window = window
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)

        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, event.window === self.window else { return false }
                    let command = event.modifierFlags.contains(.command)
                    switch (event.keyCode, command, event.charactersIgnoringModifiers?.lowercased()) {
                    case (53, _, _): self.hide()
                    case (_, true, "k"): self.state.page = .qr
                    case (_, true, "l"): self.state.page = .text
                    default: return false
                    }
                    return true
                }
                return handled ? nil : event
            }
        }
    }

    func hide() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window?.orderOut(nil)
        state.ssid = ""
    }

    func windowDidResignKey(_ notification: Notification) {
        // Typing an SSID makes the text field first responder inside this window, so only
        // close when focus actually leaves the window.
        hide()
    }
}

private struct LargeTypeView: View {
    @EnvironmentObject private var state: LargeTypeController.State
    let close: () -> Void

    var body: some View {
        ZStack {
            Palette.ground.opacity(0.94).ignoresSafeArea()
                .onTapGesture(perform: close)
            HStack(spacing: 20) {
                card(textPage, active: state.page == .text)
                card(qrPage, active: state.page == .qr).frame(width: 420)
            }
            .frame(maxWidth: 1180, maxHeight: 620)
            .padding(48)
        }
    }

    private func card<Content: View>(_ content: Content, active: Bool) -> some View {
        content
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Palette.accent.opacity(0.6), lineWidth: 1)
                } else {
                    RoundedHairline(cornerRadius: Radius.lg, color: Palette.lineStrong)
                }
            }
    }

    private var textPage: some View {
        VStack {
            HStack(spacing: 10) {
                GlassIcon(icon: .eye, size: 24)
                Text("Large Type").font(.system(size: 13, weight: .medium))
                Text("⌘L · Read it off while typing on a TV or router").font(.system(size: 12)).foregroundStyle(Palette.muted)
                Spacer()
            }
            Spacer()
            groups
            Spacer()
            HStack(spacing: 16) {
                Button(action: close) { Hint(key: "esc", label: String(localized: "Exit")) }.buttonStyle(.plain)
                Button { state.page = .qr } label: { Hint(key: "⌘K", label: String(localized: "QR Code")) }.buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { state.page = .text }
    }

    /// The secret split into groups of four, each numbered.
    private var groups: some View {
        let chars = Array(state.value)
        let chunks = stride(from: 0, to: chars.count, by: 4).map { Array(chars[$0..<min($0 + 4, chars.count)]) }
        let size: CGFloat = chars.count <= 24 ? 46 : (chars.count <= 40 ? 34 : 24)
        let perLine = chars.count <= 24 ? 6 : 5
        let lines = stride(from: 0, to: chunks.count, by: perLine).map { Array(chunks[$0..<min($0 + perLine, chunks.count)]) }
        return VStack(spacing: 28) {
            ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, line in
                HStack(spacing: 20) {
                    ForEach(Array(line.enumerated()), id: \.offset) { i, chunk in
                        let start = (lineIndex * perLine + i) * 4
                        VStack(spacing: 14) {
                            SecretText.attributed(String(chunk), size: size)
                            Text("\(start + 1)–\(start + chunk.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.faint)
                        }
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(SecretText.spokenDescription(state.value))
    }

    private var qrPage: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                GlassIcon(icon: .devices, size: 24)
                Text(state.ssid.isEmpty ? String(localized: "Scan to get it") : String(localized: "Scan to join Wi-Fi")).font(.system(size: 13, weight: .medium))
                Text("⌘K · Generated on this Mac").font(.system(size: 12)).foregroundStyle(Palette.muted)
                Spacer()
            }
            Spacer()
            if let image = QRCode.image(for: payload) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 228, height: 228)
                    .padding(18)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedHairline(cornerRadius: Radius.md, color: Palette.lineStrong))
                    .accessibilityLabel("QR Code")
            }
            Spacer()
            TextField("Wi-Fi name (optional, makes a Wi-Fi QR code)", text: $state.ssid)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            Text(state.ssid.isEmpty ? String(localized: "Scanning gives the password as plain text") : "\(state.ssid) · WPA2")
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
        }
        .contentShape(Rectangle())
        .onTapGesture { state.page = .qr }
    }

    private var payload: String {
        guard !state.ssid.isEmpty else { return state.value }
        return "WIFI:T:WPA;S:\(QRCode.escape(state.ssid));P:\(QRCode.escape(state.value));;"
    }
}

enum QRCode {
    static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(scaled, from: scaled.extent)
    }

    /// Escapes \ ; , : " for the WIFI: URI format.
    static func escape(_ value: String) -> String {
        value.reduce(into: "") { out, c in
            if "\\;,:\"".contains(c) { out.append("\\") }
            out.append(c)
        }
    }
}
