import KeyboardShortcuts
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 528),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: OnboardingView { [weak self] in self?.finish() }.environmentObject(settings))
        self.window = window
        window.presentOnMouseScreen()
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        window?.close()
        window = nil
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var step = 0
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: hotkey
                default: promises
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)

            HStack {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(i == step ? Palette.accent : Palette.lineStrong).frame(width: i == step ? 16 : 4, height: 4)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: step)
                Spacer()
                if step == 1 {
                    Button("Back") { step -= 1 }.buttonStyle(HushButtonStyle(tone: .ghost))
                }
                Button(step == 0 ? String(localized: "Get Started") : (step == 1 ? String(localized: "Continue") : String(localized: "Done"))) {
                    if step < 2 { step += 1 } else { done() }
                }
                .buttonStyle(HushButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Palette.sunken)
            .overlay(alignment: .top) { Hairline(color: Palette.lineStrong) }
        }
        .frame(width: 380, height: 528)
        .background(Palette.surface)
        .ignoresSafeArea()
    }

    private var welcome: some View {
        VStack(spacing: 26) {
            GlassIcon(icon: .shield, size: 96)
            VStack(spacing: 10) {
                Text("Welcome to Hush").font(.system(size: 28, weight: .medium))
                Text("Press a shortcut, and a strong password\nlands quietly on your clipboard.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(4)
            }
        }
    }

    private var hotkey: some View {
        VStack(spacing: 22) {
            GlassIcon(icon: .keypad, size: 96)
            VStack(spacing: 10) {
                Text("Now, give it a try").font(.system(size: 19, weight: .medium))
                Text("Summons Hush in any app. Click to record a new shortcut.").font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
            KeyboardShortcuts.Recorder(for: .togglePanel)
                .padding(10)
                .background(Palette.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var promises: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Our promises").font(.system(size: 19, weight: .medium)).padding(.bottom, 8)
            promise(.broadcast, String(localized: "Offline"), String(localized: "The sandbox has no network access"))
            promise(.notrack, String(localized: "No traces"), String(localized: "Nothing written to disk, invisible to clipboard managers"))
            promise(.timer, String(localized: "Auto-clear"), String(localized: "Clipboard cleared \(settings.clearAfterSeconds > 0 ? settings.clearAfterSeconds : 30) s after copying"))
            promise(.braces, String(localized: "Open source"), String(localized: "MIT licensed, every line public"))
            Divider().padding(.top, 10)
            HStack {
                Text("Launch at login").font(.system(size: 13))
                Spacer()
                Toggle("", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch).tint(Palette.accent).labelsHidden()
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func promise(_ icon: Glass, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            GlassIcon(icon: icon, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.vertical, 6)
    }
}
