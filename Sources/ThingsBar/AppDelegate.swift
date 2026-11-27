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
            button.action = #selector(togglePopover(_:))
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store, openSettings: { [weak self] in
            self?.popover.performClose(nil)
            self?.settingsWindow.show()
        }))

        observeTitle()
        observeRefreshInterval()
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
