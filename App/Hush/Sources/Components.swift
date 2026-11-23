import HushCore
import SwiftUI

/// A single key cap: ↩ ⌘ esc.
struct KeyCap: View {
    let label: String
    var primary = false

    var body: some View {
        Text(label)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(primary ? Palette.onAccent : Palette.muted)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(primary ? Palette.accent : Palette.raised)
                    .shadow(color: primary ? .clear : Palette.lineStrong, radius: 0, y: 1)
            }
            .overlay {
                if !primary {
                    RoundedHairline(cornerRadius: 5, color: Palette.lineStrong)
                }
            }
    }
}

/// Footer shortcut hint: key cap + action.
struct Hint: View {
    let key: String
    let label: String
    var primary = false

    var body: some View {
        HStack(spacing: 6) {
            KeyCap(label: key, primary: primary)
            Text(label).font(.system(size: 12)).foregroundStyle(primary ? Palette.ink : Palette.muted)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

struct ModeTab: View {
    let mode: Mode
    let isActive: Bool
    /// Compact: only the active tab shows its name; the others show just the icon.
    var compact = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                GlassIcon(icon: mode.icon, size: 18, muted: !isActive)
                if !compact || isActive {
                    Text(mode.title).font(.system(size: 13)).lineLimit(1).fixedSize()
                }
            }
            .foregroundStyle(isActive ? Palette.ink : (hovering ? Palette.ink : Palette.muted))
            .padding(.leading, 8)
            .padding(.trailing, compact && !isActive ? 8 : 11)
            .frame(height: 30)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.raised)
                        .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                        .overlay(RoundedHairline(cornerRadius: 8, color: Palette.lineStrong))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(mode.title)(\(mode.number))")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// On/off option with a cobalt check.
struct Chip: View {
    let label: String
    let isOn: Bool
    var monospaced = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isOn ? Palette.accent : .clear)
                        .overlay {
                            if !isOn {
                                RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: 1)
                            }
                        }
                    if isOn {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.onAccent)
                    }
                }
                .frame(width: 14, height: 14)
                Text(label)
                    .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
                    .foregroundStyle(isOn ? Palette.ink : Palette.muted)
            }
            .padding(.leading, 8)
            .padding(.trailing, 11)
            .frame(height: 28)
            .background(isOn ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(isOn ? Palette.lineStrong : Palette.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct HushButtonStyle: ButtonStyle {
    enum Tone { case primary, secondary, ghost }
    var tone: Tone = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .frame(height: 32)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if tone == .secondary {
                    RoundedHairline(cornerRadius: 8, color: Palette.lineStrong)
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch tone {
        case .primary: Palette.onAccent
        case .secondary: Palette.ink
        case .ghost: Palette.muted
        }
    }

    private var background: Color {
        switch tone {
        case .primary: Palette.accent
        case .secondary: Palette.raised
        case .ghost: .clear
        }
    }
}

/// The 4-segment strength meter.
struct Meter: View {
    let strength: Strength

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(i < strength.filledSegments ? color : Palette.line).frame(height: 3)
            }
        }
        .animation(.easeOut(duration: 0.25), value: strength)
        .accessibilityElement()
        .accessibilityLabel(strength.accessibilityTitle)
    }

    private var color: Color {
        switch strength {
        case .weak: Palette.warn
        case .fair: Palette.muted
        case .strong, .max: Palette.accent
        }
    }
}

/// Settings row: Glass icon, title, description, trailing control.
struct SettingRow<Control: View>: View {
    let icon: Glass
    let title: String
    let detail: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 14) {
            GlassIcon(icon: icon, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13)).foregroundStyle(Palette.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 12)
    }
}

/// White rounded group used in settings.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedHairline(cornerRadius: Radius.md, color: Palette.line))
    }
}

/// Colours a secret by character kind: letters ink, digits cobalt, symbols grey.
enum SecretText {
    static func color(for character: Character) -> Color {
        switch CharacterKind(character) {
        case .letter: Palette.ink
        case .digit: Palette.accentInk
        case .symbol: Palette.muted
        }
    }

    static func attributed(_ value: String, size: CGFloat) -> Text {
        value.reduce(Text("")) { text, c in
            text + Text(String(c)).foregroundColor(color(for: c))
        }
        .font(.system(size: size, design: .monospaced))
    }

    /// VoiceOver reads each character with its kind: "capital Q, digit 7, symbol #".
    static func spokenDescription(_ value: String) -> String {
        value.map { c -> String in
            switch CharacterKind(c) {
            case .letter: c.isUppercase ? String(localized: "capital \(String(c))") : String(localized: "lowercase \(String(c))")
            case .digit: String(localized: "digit \(String(c))")
            case .symbol: String(localized: "symbol \(String(c))")
            }
        }.joined(separator: ", ")
    }
}
