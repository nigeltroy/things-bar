import AppKit
import SwiftUI

/// Borderless panel that hangs below the status item, like macOS's own menu bar
/// extras: no arrow, rounded Liquid Glass (macOS 26+; a popover material before).
///
/// It can become key (for typing) without activating the app's other windows,
/// closes on Esc, on clicks elsewhere and when another app activates, and keeps
/// its top edge pinned under the menu bar as its SwiftUI content changes height.
final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor
final class PanelController: NSObject {
    let panel: GlassPanel
    private let hosting: NSHostingView<AnyView>
    private var outsideClickMonitor: Any?
    private weak var anchor: NSStatusBarButton?
    /// Called when Esc is pressed; return true if the content handled it (e.g. went back).
    var handleEscape: () -> Bool = { false }
    var onClose: () -> Void = {}

    static let gapBelowMenuBar: CGFloat = 6

    init<Content: View>(content: Content) {
        hosting = NSHostingView(rootView: AnyView(content))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel = GlassPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
                           styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                           backing: .buffered, defer: true)
        super.init()

        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.onCancel = { [weak self] in
            guard let self else { return }
            if !self.handleEscape() { self.close() }
        }
        panel.contentView = Self.makeGlass(around: hosting)

        // Keep the top edge under the menu bar whenever the content's height changes.
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: hosting, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToContent() }
        }
        hosting.postsFrameChangedNotifications = true
        observeAppSwitches()
    }

    /// Glass on macOS 26+, the popover material before. Corners match Tahoe's menu extras.
    private static func makeGlass(around content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = Theme.panelCorner
            glass.contentView = content
            return glass
        }
        let fx = NSVisualEffectView()
        fx.material = .popover
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = Theme.panelCorner
        fx.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            content.topAnchor.constraint(equalTo: fx.topAnchor),
            content.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        return fx
    }

    /// Open from the user's point of view (true during the fade in, false during the fade out).
    private(set) var isShown = false

    func setAppearance(_ appearance: NSAppearance?) { panel.appearance = appearance }

    func show(below button: NSStatusBarButton) {
        anchor = button
        isShown = true
        fitToContent()
        // A short fade, like the system's menu bar extras (none with Reduce Motion).
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
        startMonitoringOutsideClicks()
    }

    func close() {
        guard isShown else { return }
        isShown = false
        stopMonitoringOutsideClicks()
        onClose()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return } // reopened meanwhile
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        })
    }

    /// Sizes the panel to its content and places it under the status item, clamped to the screen.
    func fitToContent() {
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        var frame = NSRect(origin: .zero, size: size)
        if let button = anchor, let buttonWindow = button.window {
            let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = buttonWindow.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? .zero
            frame.origin.x = buttonRect.minX - 8 // align text with the menu bar title
            frame.origin.x = min(max(frame.origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            frame.origin.y = buttonRect.minY - Self.gapBelowMenuBar - size.height
        } else {
            frame.origin = panel.frame.origin
            frame.origin.y = panel.frame.maxY - size.height
        }
        panel.setFrame(frame, display: true)
    }

    private func startMonitoringOutsideClicks() {
        stopMonitoringOutsideClicks()
        // Global monitors only see events for other apps' windows, i.e. clicks outside us.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func stopMonitoringOutsideClicks() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        outsideClickMonitor = nil
    }

    // Close when the user switches apps (e.g. ⌘-Tab). The panel never activates
    // ThingsBar, so watch for any app activating rather than for resigning key,
    // which menus and drag sessions also cause.
    private var activationObserver: NSObjectProtocol?
    func observeAppSwitches() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }
}
