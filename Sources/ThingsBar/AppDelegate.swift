import AppKit
import SwiftUI
import ThingsBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItem: NSStatusItem!
    private(set) var store: TodoStore!
    private(set) var tokenStore: TokenStoring!
    private(set) var panelState = PanelState()
    private(set) var panel: PanelController!
    private var refreshTimer: Timer?
    private var changeTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        tokenStore = SelfTest.isActive ? MemoryTokenStore() : KeychainTokenStore()
        store = SelfTest.isActive ? SelfTest.makeStore(tokenStore: tokenStore) : Self.makeLiveStore(tokenStore: tokenStore)
        store.hasAuthToken = tokenStore.token != nil
        let menuBarFont = NSFont.menuBarFont(ofSize: 0)
        store.measureMenuBarText = { text in
            Double((text as NSString).size(withAttributes: [.font: menuBarFont]).width)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .noImage // text only: the to-do titles are the UI
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        panel = PanelController(content: makePanelView())
        panel.handleEscape = { [weak self] in self?.panelState.back() ?? false }
        panel.onClose = { [weak self] in
            self?.panelState.editingID = nil
            self?.panelState.route = .list
            self?.statusItem.button?.highlight(false)
        }

        observeTitle()
        observeRefreshInterval()
        observeAppearance()
        watchForChanges()
        Task { await store.refresh() }

        if let dir = SelfTest.outputDirectory {
            SelfTest.run(delegate: self, outputDirectory: dir)
        }
    }

    func makePanelView() -> some View {
        PanelView(store: store, state: panelState, tokenStore: tokenStore,
                  openThings: { [weak self] in self?.openThings() },
                  sizeChanged: { [weak self] in
                      // Defer to the next turn so SwiftUI has committed the new layout.
                      DispatchQueue.main.async { self?.panel?.fitToContent() }
                  })
    }

    static func makeLiveStore(tokenStore: TokenStoring, persistence: SettingsPersisting = UserDefaultsSettings()) -> TodoStore {
        let client = LiveThingsClient(opener: WorkspaceURLOpener(), authToken: { [tokenStore] in tokenStore.token })
        return TodoStore(client: client, persistence: persistence)
    }

    /// Keeps the menu bar title in sync with the store via Observation.
    private func observeTitle() {
        withObservationTracking {
            statusItem.button?.title = store.menuBarTitle
            statusItem.button?.setAccessibilityLabel("ThingsBar: \(store.menuBarTitle)")
            // Icon: off by default, but a problem reaching Things always shows one.
            let symbol: String? = store.errorMessage != nil ? "exclamationmark.circle"
                : store.settings.showMenuBarIcon ? "checkmark.circle" : nil
            let image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            image?.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.imagePosition = image == nil ? .noImage : .imageLeading
            statusItem.button?.toolTip = store.errorMessage ?? store.visibleItems.prefix(5).map(\.title).joined(separator: "\n")
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTitle() }
        }
    }

    /// Full refresh (catalog included) on the configured interval.
    private func observeRefreshInterval() {
        let seconds = withObservationTracking { store.settings.refreshSeconds } onChange: { [weak self] in
            Task { @MainActor in self?.observeRefreshInterval() }
        }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(seconds, 15)), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.store.refresh() }
        }
    }

    /// Things has no change notifications, so poll a cheap fingerprint every 2 s and
    /// refresh only when it differs (e.g. after reordering in Things).
    private func watchForChanges() {
        changeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.store.checkForChanges() }
        }
        changeTimer?.tolerance = 0.5
    }

    private func observeAppearance() {
        let appearance = withObservationTracking { store.settings.appearance } onChange: { [weak self] in
            Task { @MainActor in self?.observeAppearance() }
        }
        panel.setAppearance(appearance.nsAppearance)
        // App-wide too: text fields' editors and menus follow the app's appearance, so
        // without this, typed text was black on the dark panel when macOS is in light mode.
        NSApp.appearance = appearance.nsAppearance
    }

    @objc func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showQuickMenu()
        } else {
            togglePanel()
        }
    }

    /// Right-click menu: act on the top to-do without opening the panel.
    func makeQuickMenu() -> NSMenu {
        let menu = NSMenu()
        if let top = store.topItem {
            let title = top.title.count > 40 ? String(top.title.prefix(39)) + "…" : top.title
            menu.addItem(withTitle: "Complete \u{201C}\(title)\u{201D}", action: #selector(completeTop), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Open in Things", action: #selector(revealTop), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: "Nothing to do", action: nil, keyEquivalent: "").isEnabled = false
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ThingsBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func showQuickMenu() {
        guard let button = statusItem.button else { return }
        panel.close()
        let menu = makeQuickMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func completeTop() { if let top = store.topItem { Task { await store.complete(top) } } }
    @objc private func revealTop() { if let top = store.topItem { Task { await store.reveal(top) } } }
    @objc private func refreshNow() { Task { await store.refresh() } }

    @objc func openSettings() {
        panelState.route = .settings
        if !panel.isShown { showPanel() }
    }

    private func openThings() {
        panel.close()
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ThingsAppleEventTransport.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func togglePanel() {
        if panel.isShown { panel.close() } else { showPanel() }
    }

    func showPanel() {
        guard let button = statusItem.button else { return }
        Task { await store.refresh() }
        button.highlight(true)
        if !SelfTest.isActive {
            panelState.opens = UserDefaults.standard.integer(forKey: "panelOpens") + 1
            UserDefaults.standard.set(panelState.opens, forKey: "panelOpens")
        }
        panel.show(below: button)
    }
}
