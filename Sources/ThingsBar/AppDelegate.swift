import AppKit
import SwiftUI
import ThingsBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private(set) var store: TodoStore!
    private(set) var tokenStore: TokenStoring!
    private(set) var settingsWindow: SettingsWindowController!
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        tokenStore = SelfTest.isActive ? MemoryTokenStore() : KeychainTokenStore()
        store = SelfTest.isActive ? SelfTest.makeStore(tokenStore: tokenStore) : Self.makeLiveStore(tokenStore: tokenStore)
        settingsWindow = SettingsWindowController(store: store, tokenStore: tokenStore)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "ThingsBar")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        store.hasAuthToken = tokenStore.token != nil
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store, openSettings: { [weak self] in
            self?.openSettings()
        }))

        observeTitle()
        observeRefreshInterval()
        observeAppearance()
        Task { await store.refresh() }

        if let dir = SelfTest.outputDirectory {
            SelfTest.run(delegate: self, outputDirectory: dir)
        }
    }

    static func makeLiveStore(tokenStore: TokenStoring, persistence: SettingsPersisting = UserDefaultsSettings()) -> TodoStore {
        let client = LiveThingsClient(opener: WorkspaceURLOpener(), authToken: { [tokenStore] in tokenStore.token })
        return TodoStore(client: client, persistence: persistence)
    }

    /// Keeps the menu bar title in sync with the store via Observation.
    private func observeTitle() {
        withObservationTracking {
            statusItem.button?.title = " " + store.menuBarTitle
            statusItem.button?.toolTip = store.errorMessage ?? store.topItem?.title
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTitle() }
        }
    }

    /// Re-creates the refresh timer whenever the interval setting changes.
    private func observeRefreshInterval() {
        let seconds = withObservationTracking { store.settings.refreshSeconds } onChange: { [weak self] in
            Task { @MainActor in self?.observeRefreshInterval() }
        }
        scheduleRefresh(every: seconds)
    }

    private func scheduleRefresh(every seconds: Int) {
        refreshTimer?.invalidate()
        let interval = TimeInterval(max(seconds, 5))
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.store.refresh() }
        }
    }

    /// Applies the Dark/Light/System preference to the popover and settings window.
    private func observeAppearance() {
        let appearance = withObservationTracking { store.settings.appearance } onChange: { [weak self] in
            Task { @MainActor in self?.observeAppearance() }
        }
        popover.appearance = appearance.nsAppearance
        settingsWindow.setAppearance(appearance.nsAppearance)
    }

    @objc func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showQuickMenu()
        } else {
            togglePopover(sender)
        }
    }

    /// Right-click menu: act on the top to-do without opening the popover.
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
        let menu = makeQuickMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func completeTop() { if let top = store.topItem { Task { await store.complete(top) } } }
    @objc private func revealTop() { if let top = store.topItem { Task { await store.reveal(top) } } }
    @objc private func refreshNow() { Task { await store.refresh() } }
    @objc func openSettings() { popover.performClose(nil); settingsWindow.show() }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            Task { await store.refresh() }
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
