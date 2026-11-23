import AppKit
import CoreImage
import HushCore
import SwiftUI

/// Design tokens from the "Hush · Mac 设计稿 v2 · Glass" canvas. Porcelain (light) / graphite (dark),
/// with the cobalt of the Glass icons as the only accent.
enum Palette {
    static let ground = dynamic(0xE4E5E8, 0x0D0E10)
    static let surface = dynamic(0xF6F6F7, 0x18191C)
    static let raised = dynamic(0xFFFFFF, 0x222327)
    static let sunken = dynamic(0xEDEEF0, 0x121315)
    static let line = dynamic(0xDFE0E3, 0x2A2B30)
    static let lineStrong = dynamic(0xC8CACF, 0x3A3C42)
    static let ink = dynamic(0x17181C, 0xECEDEF)
    static let muted = dynamic(0x62666E, 0x8E929A)
    static let faint = dynamic(0xA3A7AE, 0x55585F)
    static let accent = dynamic(0x1F63DA, 0x3A80F0)
    static let accentInk = dynamic(0x1A56C0, 0x86B2FF)
    static let accentSoft = dynamic(0xE5EDFB, 0x17243B)
    static let onAccent = Color.white
    static let warn = dynamic(0xA8502C, 0xD08360)

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
}

/// The Glass icon set from `icons/glass`.
enum Glass: String, CaseIterable {
    case shield, eye, timer, sliders, gear, copy, shuffle, open, tag, broadcast
    case keypad, lines, braces, devices, notrack, megaphone, gauge, flag, globe

    var assetName: String { "glass.\(rawValue)" }

    var nsImage: NSImage? { NSImage(named: assetName) }

    /// A copy sized for menus.
    @MainActor
    func menuImage(size: CGFloat = 16) -> NSImage? {
        GlassRenderer.image(self, points: size)
    }
}

/// The Glass artwork ships as 384 px bitmaps. Letting AppKit or SwiftUI shrink them 10–20×
/// while drawing aliases the soft gradients into grain, so every size is resampled once with
/// a Lanczos filter to its exact pixel size and cached.
@MainActor
enum GlassRenderer {
    private static var cache: [String: NSImage] = [:]
    private static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    static func image(_ icon: Glass, points: CGFloat) -> NSImage? {
        let scale = max(NSScreen.screens.map(\.backingScaleFactor).max() ?? 2, 2)
        let key = "\(icon.rawValue)@\(points)x\(scale)"
        if let cached = cache[key] { return cached }
        guard let source = icon.nsImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let pixels = (points * scale).rounded()
        let input = CIImage(cgImage: source)
        let filter = CIFilter(name: "CILanczosScaleTransform")!
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(pixels / CGFloat(source.height), forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let output = filter.outputImage,
              let scaled = context.createCGImage(output, from: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        else { return nil }

        let rep = NSBitmapImageRep(cgImage: scaled)
        rep.size = NSSize(width: points, height: points)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        cache[key] = image
        return image
    }
}

struct GlassIcon: View {
    let icon: Glass
    var size: CGFloat = 18
    /// Idle state: desaturated and dimmed so the active item carries the colour.
    var muted = false

    var body: some View {
        Group {
            if let image = GlassRenderer.image(icon, points: size) {
                Image(nsImage: image).interpolation(.high)
            } else {
                Image(icon.assetName).resizable().interpolation(.high)
            }
        }
        .frame(width: size, height: size)
        .saturation(muted ? 0.2 : 1)
        .opacity(muted ? 0.55 : 1)
        .accessibilityHidden(true)
    }
}

// MARK: - Copy for core types

extension Mode {
    var title: String {
        switch self {
        case .random: String(localized: "Random")
        case .passphrase: String(localized: "Phrase")
        case .pin: "PIN"
        case .pronounceable: String(localized: "Syllables")
        case .key: String(localized: "Key")
        }
    }

    var icon: Glass {
        switch self {
        case .random: .shuffle
        case .passphrase: .lines
        case .pin: .keypad
        case .pronounceable: .megaphone
        case .key: .braces
        }
    }

    /// 1-based shortcut number shown in the panel.
    var number: Int { Mode.allCases.firstIndex(of: self)! + 1 }
}

extension Strength {
    var title: String {
        switch self {
        case .weak: String(localized: "Weak")
        case .fair: String(localized: "Fair")
        case .strong: String(localized: "Strong")
        case .max: String(localized: "Very strong")
        }
    }

    var accessibilityTitle: String { String(localized: "Strength: \(title)") }
}

extension CrackTime.Magnitude {
    var summary: String {
        switch self {
        case .instant: String(localized: "Cracked instantly in an offline attack")
        case .seconds(let n): String(localized: "About \(n) seconds to brute-force offline")
        case .minutes(let n): String(localized: "About \(n) minutes to brute-force offline")
        case .hours(let n): String(localized: "About \(n) hours to brute-force offline")
        case .days(let n): String(localized: "About \(n) days to brute-force offline")
        case .years(let n): String(localized: "About \(n) years to brute-force offline")
        case .powerOfTenYears(let e): String(localized: "About 10\(Self.superscript(e)) years to brute-force offline")
        }
    }

    private static func superscript(_ n: Int) -> String {
        let map: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(n).compactMap { map[$0] })
    }
}

extension Preset {
    /// The preset's name in the user's language. `name` (English) is what the CLI prints.
    var displayName: String {
        switch id {
        case "default": String(localized: "Strong default")
        case "compatible": String(localized: "Compatible")
        case "wifi": String(localized: "Wi-Fi")
        case "pin6": String(localized: "6-digit PIN")
        case "devkey": String(localized: "Developer key")
        case "memorable": String(localized: "Memorable")
        default: name
        }
    }
}

extension Preset {
    var icon: Glass {
        switch id {
        case "default": .shield
        case "wifi": .broadcast
        case "pin6": .keypad
        case "devkey": .braces
        case "memorable": .lines
        default: config.mode.icon
        }
    }
}

extension KeyFormat {
    var title: String {
        switch self {
        case .hex: "Hex"
        case .base64: "Base64"
        case .base64url: "Base64URL"
        case .uuid: "UUID v4"
        }
    }
}

extension NSWindow {
    /// Centers the window on the display under the mouse and brings it to the front,
    /// even when the app could not take focus (a menu bar app launched from Xcode or Finder).
    @MainActor
    func presentOnMouseScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2 + visible.height * 0.08))
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
}

// MARK: - Hairlines

/// A rounded border exactly one device pixel wide. A fixed 0.5 pt stroke is half a pixel on
/// 1x displays: straight edges fade out while the anti-aliased corners stay dark, which reads
/// as grey arcs at the four corners.
struct RoundedHairline: View {
    var cornerRadius: CGFloat
    var color: Color
    @Environment(\.displayScale) private var scale

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(color, lineWidth: 1 / max(scale, 1))
    }
}

/// A horizontal rule one device pixel tall.
struct Hairline: View {
    var color: Color
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle().fill(color).frame(height: 1 / max(scale, 1))
    }
}
