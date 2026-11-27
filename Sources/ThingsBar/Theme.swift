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
    // Values are set by the self-test's contrast audit (ContrastAudit.swift): every text
    // token reaches WCAG's 4.5:1 for small text, and glyph tokens 3:1, in dark and light,
    // on the panel and on field fills, over worst-case glass.
    /// Meta text (projects, deadlines, values).
    static let textSecondary = ink(0.80, 0.72, contrast: 0.88, 0.84)
    /// Quiet text (tags, footer, notes): the faintest text, still 4.5:1 or more.
    static let textMuted = ink(0.72, 0.64, contrast: 0.84, 0.78)
    /// Placeholders in text fields. As legible as quiet text (an invisible prompt
    /// hides what the field is for), told apart from typed text by typed text's
    /// primary color.
    /// Drawn by `PlaceholderOverlay`: macOS ignores a SwiftUI prompt's color and uses its
    /// own, much fainter placeholder color.
    static let placeholder = ink(0.72, 0.64, contrast: 0.84, 0.78)
    /// Glyphs only, never text: 3:1, the minimum for meaningful graphics.
    static let textTertiary = ink(0.48, 0.48, contrast: 0.62, 0.62)
    /// Outline of text fields, so an empty field is visible as a field.
    static let fieldBorder = ink(0.12, 0.12, contrast: 0.35, 0.35)
    static let fieldBorderFocused = ink(0.30, 0.30, contrast: 0.55, 0.55)
    static let separator = ink(0.08, 0.08, contrast: 0.25, 0.25)

    /// Row hover: a color shift only, never a size change.
    static let hoverFill = ink(0.07, 0.07, contrast: 0.12, 0.12)
    /// Pressed, focused and field backgrounds.
    static let fieldFill = ink(0.05, 0.05, contrast: 0.08, 0.08)
    /// Chips and banners. Kept low in dark mode: a lighter fill under white text lowers contrast.
    static let strongFill = ink(0.10, 0.10, contrast: 0.14, 0.18)
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

    /// `animation`, or none when Reduce Motion is on.
    static func motion(_ animation: Animation) -> Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
    }

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
        // Disabled: a plain chip with secondary (still 4.5:1) text, not a faded button that's hard to read.
        let solid = prominent && isEnabled
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(solid ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                             : AnyShapeStyle(isEnabled ? Theme.textPrimary : Theme.textSecondary))
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(solid ? AnyShapeStyle(Theme.textPrimary) : AnyShapeStyle(Theme.strongFill)))
            .opacity(configuration.isPressed ? 0.7 : 1)
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

/// Draws a text field's placeholder in `Theme.placeholder` while the field is empty.
/// Use with an empty prompt: macOS draws SwiftUI prompts in its own faint color.
struct PlaceholderOverlay: ViewModifier {
    let text: String
    let isEmpty: Bool
    var alignment: Alignment = .leading

    func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            if isEmpty {
                Text(text).foregroundStyle(Theme.placeholder).lineLimit(1)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func placeholder(_ text: String, when isEmpty: Bool, alignment: Alignment = .leading) -> some View {
        modifier(PlaceholderOverlay(text: text, isEmpty: isEmpty, alignment: alignment))
    }
}
