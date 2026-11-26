import AppKit

// Plain AppKit entry point: menu bar apps need precise control of NSStatusItem,
// which SwiftUI's MenuBarExtra does not expose.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // no Dock icon (matches LSUIElement)
    withExtendedLifetime(delegate) { app.run() }
}
