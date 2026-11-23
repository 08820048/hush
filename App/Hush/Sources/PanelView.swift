import HushCore
import SwiftUI

/// Callbacks the panel's buttons trigger; owned by `PanelController`.
@MainActor
final class PanelActions: ObservableObject {
    var copyAndClose: () -> Void = {}
    var paste: () -> Void = {}
    var close: () -> Void = {}
    var showLargeType: () -> Void = {}
    var showQR: () -> Void = {}
}

struct PanelView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var actions: PanelActions

    static let width: CGFloat = 620

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            PasswordStage()
            StrengthRow()
            Divider().overlay(Palette.lineStrong)
            Group {
                if model.form == .savePreset {
                    SavePresetForm()
                } else if model.form == .website {
                    WebsiteForm()
                } else if model.showsHistory {
                    HistoryList()
                } else {
                    OptionsView()
                }
            }
            .frame(height: 104)
            footer
        }
        .frame(width: Self.width)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedHairline(cornerRadius: Radius.lg, color: Color.black.opacity(0.14)))
    }

    private var modeBar: some View {
        HStack(spacing: 2) {
            ForEach(Mode.allCases, id: \.self) { mode in
                ModeTab(mode: mode, isActive: model.mode == mode) { model.select(mode) }
            }
            Spacer(minLength: 8)
            PresetPicker()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button(action: actions.copyAndClose) { Hint(key: "↩", label: String(localized: "Copy"), primary: true) }.buttonStyle(.plain)
            Button(action: actions.paste) { Hint(key: "⌘↩", label: model.targetAppName.map { String(localized: "Paste into \($0)") } ?? String(localized: "Paste")) }.buttonStyle(.plain)
            Button { model.regenerate() } label: { Hint(key: "␣", label: String(localized: "New")) }.buttonStyle(.plain)
            Button(action: actions.showLargeType) { Hint(key: "⌘L", label: String(localized: "Large Type")) }.buttonStyle(.plain)
            Spacer()
            Button(action: actions.close) { Hint(key: "esc", label: String(localized: "Close")) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Palette.sunken)
        .overlay(alignment: .top) { Hairline(color: Palette.lineStrong) }
    }
}

// MARK: - Preset picker

private struct PresetPicker: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presets: PresetStore

    var body: some View {
        Menu {
            ForEach(Array(model.presets.all.enumerated()), id: \.element.id) { index, preset in
                if index == Preset.builtIns.count { Divider() }
                if index < 9 {
                    Button(preset.displayName) { model.apply(preset) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                } else {
                    Button(preset.displayName) { model.apply(preset) }
                }
            }
            Divider()
            Button("Follow a Website’s Rules…") { model.beginChoosingWebsite() }
                .keyboardShortcut("d", modifiers: .command)
            Button("Save as Preset…") { model.beginSavingPreset() }
                .keyboardShortcut("s", modifiers: .command)
        } label: {
            // Menu labels render images at their natural size, so use a pre-sized bitmap.
            if let icon = Glass.tag.menuImage(size: 16) {
                Image(nsImage: icon)
            }
            Text(model.siteLabel ?? model.presetName ?? String(localized: "Custom"))
        }
        .menuStyle(.borderlessButton)
        .font(.system(size: 12))
        .foregroundStyle(Palette.muted)
        .fixedSize()
        .padding(.horizontal, 6)
        .frame(height: 30)
        .help("Presets")
    }
}

// MARK: - Save as preset

private struct SavePresetForm: View {
    @EnvironmentObject private var model: AppModel
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                GlassIcon(icon: .tag, size: 20)
                Text("Save the current settings as a preset").font(.system(size: 13)).foregroundStyle(Palette.ink)
            }
            HStack(spacing: 8) {
                TextField("Preset name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(save)
                Button("Cancel") { model.form = nil }
                    .buttonStyle(HushButtonStyle(tone: .secondary))
                Button("Save", action: save)
                    .buttonStyle(HushButtonStyle(tone: .primary))
                    .disabled(PresetStore.clean(name) == nil)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear {
            name = model.suggestedPresetName
            focused = true
        }
    }

    private func save() {
        model.savePreset(named: name)
    }
}

// MARK: - Website rules

private struct WebsiteForm: View {
    @EnvironmentObject private var model: AppModel
    @State private var input = ""
    @FocusState private var focused: Bool

    private var match: SiteRules.Match? { SiteRules.lookup(input) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                GlassIcon(icon: .globe, size: 20)
                Text("Follow a website’s password rules").font(.system(size: 13)).foregroundStyle(Palette.ink)
            }
            HStack(spacing: 8) {
                TextField("example.com or a link", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(apply)
                Button("Cancel") { model.form = nil }
                    .buttonStyle(HushButtonStyle(tone: .secondary))
                Button("Use", action: apply)
                    .buttonStyle(HushButtonStyle(tone: .primary))
                    .disabled(SiteRules.normalizedHost(input) == nil)
            }
            Text(status)
                .font(.system(size: 12))
                .foregroundStyle(match == nil ? Palette.muted : Palette.accentInk)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear { focused = true }
    }

    private var status: String {
        if let match {
            return "\(match.domain) · \(RulesSummary.describe(match.rules))"
        }
        if let host = SiteRules.normalizedHost(input) {
            return String(localized: "No known rules for \(host). The default password works on most sites.")
        }
        return String(localized: "Hush knows the rules of \(SiteRules.count) websites, offline.")
    }

    private func apply() {
        guard SiteRules.normalizedHost(input) != nil else { return }
        model.applyWebsite(input)
    }
}

/// A short, human description of password rules: "6–16 characters · needs a digit · no symbols".
enum RulesSummary {
    static func describe(_ rules: PasswordRules) -> String {
        var parts: [String] = []
        switch (rules.minLength, rules.maxLength) {
        case let (min?, max?) where min == max: parts.append(String(localized: "exactly \(min) characters"))
        case let (min?, max?): parts.append(String(localized: "\(min)–\(max) characters"))
        case let (min?, nil): parts.append(String(localized: "at least \(min) characters"))
        case let (nil, max?): parts.append(String(localized: "up to \(max) characters"))
        case (nil, nil): break
        }

        let permitted = rules.permittedCharacters
        let symbols = CharacterPools.allSymbols.filter(permitted.contains)
        if symbols.isEmpty {
            parts.append(String(localized: "no symbols"))
        } else if symbols.count < CharacterPools.allSymbols.count {
            parts.append(String(localized: "symbols \(symbols)"))
        }
        if let run = rules.maxConsecutive {
            parts.append(String(localized: "no character more than \(run)× in a row"))
        }
        return parts.isEmpty ? String(localized: "no special requirements") : parts.joined(separator: " · ")
    }
}

// MARK: - Password stage

private struct PasswordStage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var actions: PanelActions

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Group {
                if let error = model.errorMessage {
                    Text(error).font(.system(size: 15)).foregroundStyle(Palette.warn)
                } else {
                    PasswordText()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                StageButton(icon: .eye, help: model.isRevealed ? String(localized: "Hide") : String(localized: "Show")) { model.isRevealed.toggle() }
                StageButton(icon: .shuffle, help: String(localized: "New (Space)")) { model.regenerate() }
            }
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 98)
        .background(Palette.sunken, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedHairline(cornerRadius: Radius.md, color: Palette.line))
        .padding(.horizontal, 14)
        .onDrag { NSItemProvider(object: (model.secret?.value ?? "") as NSString) }
    }
}

private struct StageButton: View {
    let icon: Glass
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassIcon(icon: icon, size: 20)
                .frame(width: 34, height: 34)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedHairline(cornerRadius: 8, color: Palette.lineStrong))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct PasswordText: View {
    @EnvironmentObject private var model: AppModel
    @State private var hoveredIndex: Int?

    var body: some View {
        let value = model.display
        let size = fontSize(for: value.count)
        Group {
            if !model.isRevealed {
                Text(String(repeating: "•", count: value.count))
                    .font(.system(size: size, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            } else if case .random = model.config, value.count <= 36 {
                tappable(value, size: size)
            } else if case .pin = model.config {
                // All digits: colouring them would make the whole PIN cobalt.
                Text(value).font(.system(size: size, design: .monospaced)).tracking(4).foregroundStyle(Palette.ink)
            } else {
                SecretText.attributed(value, size: size)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.disabled)
        .accessibilityElement()
        .accessibilityLabel(model.isRevealed ? SecretText.spokenDescription(model.secret?.value ?? "") : String(localized: "Password hidden"))
    }

    /// Each character is its own hit target: click to re-roll just that one.
    private func tappable(_ value: String, size: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(value.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(.system(size: size, design: .monospaced))
                    .foregroundStyle(SecretText.color(for: character))
                    .padding(.vertical, 3)
                    .background {
                        if hoveredIndex == index {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Palette.raised)
                                .overlay(RoundedHairline(cornerRadius: 4, color: Palette.lineStrong))
                        }
                    }
                    .onHover { inside in
                        if inside { hoveredIndex = index } else if hoveredIndex == index { hoveredIndex = nil }
                    }
                    .onTapGesture { model.reroll(at: index) }
                    .help("Click to re-roll this character")
            }
        }
        .fixedSize()
    }

    private func fontSize(for count: Int) -> CGFloat {
        switch count {
        case ...22: 30
        case ...28: 24
        case ...36: 19
        default: 16
        }
    }
}

// MARK: - Strength

private struct StrengthRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let bits = model.config.entropyBits
        let strength = Strength(bits: bits)
        HStack(spacing: 14) {
            GlassIcon(icon: strength == .max ? .shield : .gauge, size: 30)
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(strength.title).font(.system(size: 13, weight: .medium)).foregroundStyle(strength == .weak ? Palette.warn : Palette.ink)
                    Text("·  \(Int(bits.rounded())) bits").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Spacer()
                    Text(detail(bits: bits)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Meter(strength: strength)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .accessibilityElement(children: .combine)
    }

    private func detail(bits: Double) -> String {
        switch model.config {
        case .key(let o):
            return o.format == .uuid ? String(localized: "UUID v4 · 122 random bits") : String(localized: "\(o.bytes) bytes · \(o.format.title)")
        case .pin:
            return String(localized: "Only for systems that limit failed attempts")
        default:
            return CrackTime.magnitude(forBits: bits).summary
        }
    }
}

// MARK: - Options per mode

private struct OptionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.config {
            case .random(let o): randomOptions(o)
            case .passphrase(let o): passphraseOptions(o)
            case .pin(let o): pinOptions(o)
            case .pronounceable(let o): pronounceableOptions(o)
            case .key(let o): keyOptions(o)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func randomOptions(_ o: RandomOptions) -> some View {
        SliderRow(label: String(localized: "Length"), value: o.length, range: 4...64) { v in var n = o; n.length = v; model.update(.random(n)) }
        ChipRow {
            Chip(label: "A–Z", isOn: o.uppercase) { var n = o; n.uppercase.toggle(); model.update(.random(n)) }
            Chip(label: "a–z", isOn: o.lowercase) { var n = o; n.lowercase.toggle(); model.update(.random(n)) }
            Chip(label: "0–9", isOn: o.digits) { var n = o; n.digits.toggle(); model.update(.random(n)) }
            Chip(label: o.symbolSet == CharacterPools.allSymbols ? "#$&!" : o.symbolSet, isOn: o.symbols, monospaced: true) { var n = o; n.symbols.toggle(); model.update(.random(n)) }
            Spacer().frame(width: 12)
            Chip(label: String(localized: "No look-alikes"), isOn: o.excludeAmbiguous) { var n = o; n.excludeAmbiguous.toggle(); model.update(.random(n)) }
        }
    }

    @ViewBuilder private func passphraseOptions(_ o: PassphraseOptions) -> some View {
        SliderRow(label: String(localized: "Words"), value: o.wordCount, range: PassphraseOptions.wordCountRange) { v in var n = o; n.wordCount = v; model.update(.passphrase(n)) }
        ChipRow {
            ForEach(PassphraseOptions.separators, id: \.self) { sep in
                Chip(label: sep == " " ? String(localized: "Space") : sep, isOn: o.separator == sep, monospaced: sep != " ") { var n = o; n.separator = sep; model.update(.passphrase(n)) }
            }
            Spacer().frame(width: 12)
            Chip(label: String(localized: "Capitalize"), isOn: o.capitalize) { var n = o; n.capitalize.toggle(); model.update(.passphrase(n)) }
            Chip(label: String(localized: "Add a digit"), isOn: o.appendDigit) { var n = o; n.appendDigit.toggle(); model.update(.passphrase(n)) }
        }
    }

    @ViewBuilder private func pinOptions(_ o: PINOptions) -> some View {
        SliderRow(label: String(localized: "Digits"), value: o.length, range: PINOptions.lengthRange) { v in var n = o; n.length = v; model.update(.pin(n)) }
        ChipRow {
            ForEach([4, 6, 8], id: \.self) { len in
                Chip(label: String(localized: "\(len) digits"), isOn: o.length == len) { var n = o; n.length = len; model.update(.pin(n)) }
            }
            Spacer().frame(width: 12)
            Chip(label: String(localized: "Avoid 123456, dates…"), isOn: o.avoidWeakPatterns) { var n = o; n.avoidWeakPatterns.toggle(); model.update(.pin(n)) }
        }
    }

    @ViewBuilder private func pronounceableOptions(_ o: PronounceableOptions) -> some View {
        SliderRow(label: String(localized: "Groups"), value: o.groups, range: PronounceableOptions.groupRange) { v in var n = o; n.groups = v; model.update(.pronounceable(n)) }
        ChipRow {
            Chip(label: String(localized: "Add two digits"), isOn: o.digits > 0) { var n = o; n.digits = o.digits > 0 ? 0 : 2; model.update(.pronounceable(n)) }
        }
    }

    @ViewBuilder private func keyOptions(_ o: KeyOptions) -> some View {
        SliderRow(label: String(localized: "Bytes"), value: o.bytes, range: 8...128, step: 8, disabled: o.format == .uuid) { v in var n = o; n.bytes = v; model.update(.key(n)) }
        ChipRow {
            ForEach(KeyFormat.allCases, id: \.self) { format in
                Chip(label: format.title, isOn: o.format == format) { var n = o; n.format = format; model.update(.key(n)) }
            }
        }
    }
}

private struct ChipRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 6) { content }
            .padding(.leading, 56)
    }
}

private struct SliderRow: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var disabled = false
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1).fixedSize().frame(minWidth: 40, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(min(max(value, range.lowerBound), range.upperBound)) },
                    set: { raw in
                        let snapped = Int((raw / Double(step)).rounded()) * step
                        let clamped = min(max(snapped, range.lowerBound), range.upperBound)
                        if clamped != value { onChange(clamped) }
                    }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            .tint(Palette.accent)
            .controlSize(.small)
            .disabled(disabled)
            .accessibilityLabel(label)
            Text("\(value)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(disabled ? Palette.faint : Palette.ink)
                .frame(width: 36, height: 24)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedHairline(cornerRadius: 6, color: Palette.lineStrong))
        }
    }
}

// MARK: - History (⌘Y)

private struct HistoryList: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        if history.entries.isEmpty {
            VStack(spacing: 6) {
                GlassIcon(icon: .timer, size: 24)
                Text("Nothing yet · Kept in memory only, wiped after 5 minutes or when the screen locks").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(history.entries) { entry in HistoryRow(entry: entry) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var model: AppModel
    let entry: HistoryStore.Entry
    @State private var hovering = false

    var body: some View {
        Button { model.copy(entry.value, mode: entry.mode) } label: {
            HStack(spacing: 10) {
                GlassIcon(icon: entry.mode.icon, size: 16)
                Text(hovering ? entry.value : masked(entry.value))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(entry.date, style: .relative).font(.system(size: 11)).foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(hovering ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Click to copy")
    }

    private func masked(_ value: String) -> String {
        guard value.count > 8 else { return String(repeating: "•", count: value.count) }
        return String(value.prefix(4)) + String(repeating: "•", count: 8) + String(value.suffix(3))
    }
}
