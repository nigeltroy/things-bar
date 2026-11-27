import ThingsBarCore
import AppKit
import SwiftUI

/// Low-contrast palette modelled on Claude's warm dark UI: charcoal backgrounds,
/// off-white (never pure white) text, a muted clay accent.
enum Theme {
    static let background = dynamic(light: 0xFAF9F5, dark: 0x262624)
    static let surface = dynamic(light: 0xF0EEE6, dark: 0x30302E)
    static let surfaceHover = dynamic(light: 0xE8E6DC, dark: 0x383836)
    static let border = dynamic(light: 0x1F1E1D, dark: 0xFAF9F5, lightAlpha: 0.10, darkAlpha: 0.08)
    static let textPrimary = dynamic(light: 0x3D3D3A, dark: 0xE6E4DC)
    static let textSecondary = dynamic(light: 0x73726C, dark: 0xA6A39A)
    static let textTertiary = dynamic(light: 0x9C9A92, dark: 0x75736C)
    static let accent = dynamic(light: 0xC96442, dark: 0xD97757)
    static let accentSoft = dynamic(light: 0xC96442, dark: 0xD97757, lightAlpha: 0.12, darkAlpha: 0.14)
    static let deadline = dynamic(light: 0xB0702A, dark: 0xD4A35E)
    static let danger = dynamic(light: 0xB5473A, dark: 0xE08A7E)

    static let corner: CGFloat = 8

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return rgb(isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}


extension AppSettings.Appearance {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
    }
}

/// Quiet icon button used in rows and the footer.
struct IconButton: View {
    let systemName: String
    let help: String
    var role: ButtonRole?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.surfaceHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// Filled, low-contrast text button.
struct SoftButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? Color(nsColor: .init(srgbRed: 0.15, green: 0.15, blue: 0.14, alpha: 1)) : Theme.textPrimary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(prominent ? Theme.accent : Theme.surfaceHover))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
