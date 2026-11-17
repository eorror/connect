import AppKit
import CoreText
import SwiftUI

/// Colours, type and surfaces copied from the Cairn design tokens (light glass on flat grey,
/// with the matching dark set).
enum Theme {
    static let bg         = dynamic(light: hex(0xECEEF1), dark: hex(0x101114))
    static let ink        = dynamic(light: hex(0x15171A), dark: hex(0xECEEF1))
    static let ink2       = dynamic(light: hex(0x4F555C), dark: hex(0xA9AFB7))
    static let ink3       = dynamic(light: hex(0x656B73), dark: hex(0x8A9099))
    static let onInk      = dynamic(light: hex(0xFFFFFF), dark: hex(0x101114))
    static let glass      = dynamic(light: .white.withAlphaComponent(0.62), dark: .white.withAlphaComponent(0.055))
    static let glass2     = dynamic(light: .white.withAlphaComponent(0.90), dark: .white.withAlphaComponent(0.09))
    static let stroke     = dynamic(light: .white.withAlphaComponent(0.95), dark: .white.withAlphaComponent(0.08))
    static let line       = dynamic(light: hex(0x15171A, 0.07), dark: .white.withAlphaComponent(0.07))
    static let shadow     = dynamic(light: NSColor(red: 40/255, green: 50/255, blue: 80/255, alpha: 0.08),
                                    dark: .black.withAlphaComponent(0.45))
    static let solid      = dynamic(light: hex(0xFFFFFF), dark: hex(0x2A2D33))
    static let panel      = dynamic(light: .white.withAlphaComponent(0.92),
                                    dark: NSColor(red: 34/255, green: 36/255, blue: 42/255, alpha: 0.94))
    static let accent     = dynamic(light: hex(0x2B4ACB), dark: hex(0xF2EEE6))
    static let accentSoft = dynamic(light: hex(0x2B4ACB, 0.10), dark: hex(0xF2EEE6, 0.10))

    /// Cairn project swatches, mixed about 30% into the base like project-tinted task blocks.
    static let theirTint  = tint(0xD98AA8)   // Pink
    static let mineTint   = tint(0x6E8EF0)   // Blue
    static let theirDot   = Color(nsColor: hex(0xD98AA8))
    static let mineDot    = Color(nsColor: hex(0x6E8EF0))

    // MARK: Type (Instrument Serif / Instrument Sans when bundled, close system faces otherwise)

    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        let name = italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular"
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        let f = Font.system(size: size, design: .serif)
        return italic ? f.italic() : f
    }

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "InstrumentSans-SemiBold"
        case .medium: name = "InstrumentSans-Medium"
        default: name = "InstrumentSans-Regular"
        }
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .system(size: size, weight: weight)
    }

    /// Registers any fonts shipped in Contents/Resources/Fonts.
    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for url in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: Helpers

    private static func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func tint(_ v: UInt32) -> Color {
        let c = hex(v)
        func mix(_ base: NSColor, _ amount: CGFloat) -> NSColor {
            c.blended(withFraction: 1 - amount, of: base) ?? c
        }
        return dynamic(light: mix(hex(0xFFFFFF), 0.30), dark: mix(hex(0x1B1D21), 0.30))
    }
}

// MARK: - Surfaces

/// Cairn glass card: translucent fill over blur, 1pt light edge, soft blue-black shadow.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.glass))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                    .shadow(color: Theme.shadow, radius: 32, y: 12)
            }
    }
}

extension View {
    func glassCard(radius: CGFloat = 22) -> some View { modifier(GlassCard(radius: radius)) }
}

/// Filled ink pill (primary action) or glass pill (secondary), as in Cairn.
struct PillButtonStyle: ButtonStyle {
    var primary = true
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(12, .semibold))
            .foregroundStyle(primary ? Theme.onInk : Theme.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(primary ? Theme.ink : Theme.glass2)
                    .overlay(Capsule().strokeBorder(primary ? .clear : Theme.line, lineWidth: 1))
            }
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillSecondary: PillButtonStyle { PillButtonStyle(primary: false) }
}
