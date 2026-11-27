import AppKit
import SwiftUI
import ThingsBarCore

/// Grayscale design tokens for content on Liquid Glass.
///
/// Text uses the system's hierarchical label styles (primary, secondary, tertiary),
/// which stay legible over glass in light and dark mode. Emphasis comes from weight
/// and fills, never from hue.
enum Theme {
    // Each token has a normal and an Increase Contrast value (System Settings →
    // Accessibility → Display), resolved per appearance by AppKit.
    static let textPrimary = Color.primary
    /// Meta text (projects, deadlines, values): about 5.5:1 dark, 6.5:1 light on glass.
    static let textSecondary = ink(0.68, 0.66, contrast: 0.82, 0.80)
    /// Quiet text (tags, footer, notes, placeholders): the faintest text that still
    /// reaches WCAG's 4.5:1 for small text over glass.
    static let textMuted = ink(0.56, 0.57, contrast: 0.72, 0.72)
    /// Decorative glyphs only, never text.
    static let textTertiary = ink(0.30, 0.28, contrast: 0.55, 0.55)
    static let separator = ink(0.08, 0.08, contrast: 0.25, 0.25)

    /// Row hover: a color shift only, never a size change.
    static let hoverFill = ink(0.07, 0.07, contrast: 0.16, 0.14)
    /// Pressed, focused and field backgrounds.
    static let fieldFill = ink(0.05, 0.05, contrast: 0.12, 0.10)
    static let strongFill = ink(0.12, 0.12, contrast: 0.24, 0.22)
    /// Drawn around the panel only with Increase Contrast, as system panels do.
    static let panelBorder = ink(0, 0, contrast: 0.45, 0.40)

    // Geometry (points). Rows are inset from the panel edge so hover fills sit
    // concentrically inside the panel's 16 pt corners.
    static let panelCorner: CGFloat = 16
    static let rowCorner: CGFloat = panelCorner - edgeInset // concentric with the panel
    static let panelWidth: CGFloat = 340
    static let edgeInset: CGFloat = 6
    static let textInset: CGFloat = 10

    static let hoverAnimation = Animation.easeOut(duration: 0.12)

    /// System Settings → Accessibility → Display → Increase Contrast (or a self-test override).
    nonisolated(unsafe) static var forceIncreaseContrast = false
    static var increaseContrast: Bool {
        forceIncreaseContrast || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    /// White (dark mode) or black (light mode) at an opacity, so the gray takes on a
    /// little of the glass behind it. `contrast` values apply with Increase Contrast.
    private static func ink(_ dark: CGFloat, _ light: CGFloat, contrast hcDark: CGFloat, _ hcLight: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let more = increaseContrast
            return isDark ? NSColor(white: 1, alpha: more ? hcDark : dark) : NSColor(white: 0, alpha: more ? hcLight : light)
        })
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

/// Quiet icon button: tertiary glyph, hover fill. Fixed size, so hovering never moves anything.
struct IconButton: View {
    let systemName: String
    let help: String
    var size: CGFloat = 24
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.hoverFill : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled() // no blue focus ring: the panel is grayscale
        .help(help)
        .accessibilityLabel(help)
        .onHover { h in withAnimation(Theme.hoverAnimation) { hovering = h } }
    }
}

/// Low-contrast text button. `prominent` inverts to a solid label-colored capsule.
struct SoftButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(Theme.textPrimary))
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(prominent ? AnyShapeStyle(Theme.textPrimary) : AnyShapeStyle(Theme.strongFill)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

/// Small uppercase-free section header, as in Control Center.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.textInset)
            .padding(.top, 10).padding(.bottom, 2)
    }
}
