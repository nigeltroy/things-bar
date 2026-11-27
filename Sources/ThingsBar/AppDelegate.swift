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
    private(set) var updates: UpdateChecker!
    private var updateTimer: Timer?
    private var tokenVerifier: TokenVerifier?
    private var refreshTimer: Timer?
    private var changeTimer: Timer?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        tokenStore = SelfTest.isActive ? MemoryTokenStore() : KeychainTokenStore()
        store = SelfTest.isActive ? SelfTest.makeStore(tokenStore: tokenStore) : Self.makeLiveStore(tokenStore: tokenStore)
        store.hasAuthToken = tokenStore.token != nil
        let menuBarFont = NSFont.menuBarFont(ofSize: 0)
        updates = SelfTest.isActive ? SelfTest.makeUpdateChecker() : UpdateChecker()
        if SelfTest.isActive && !SelfTest.useLiveThings {
            panelState.verifyToken = { $0 == "fixture-token" ? .valid : .invalid(TokenCheck.rejected) }
        } else {
            let verifier = TokenVerifier()
            tokenVerifier = verifier
            panelState.verifyToken = { await verifier.verify($0) }
        }
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
            self?.panelState.selectedID = nil
            self?.panelState.route = .list
            self?.statusItem.button?.highlight(false)
        }

        // Arrow keys, Space, Return and ⌘⌫ drive the list unless a text field is being edited.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode, modifiers = event.modifierFlags
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.store.hasAuthToken, self.panel.isShown, self.panel.panel.isKeyWindow,
                      !(self.panel.panel.firstResponder is NSTextView) else { return false }
                return ListKeys.handle(keyCode: keyCode, modifiers: modifiers, store: self.store, state: self.panelState)
            }
            return handled ? nil : event
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelState.displayOptionsVersion += 1 }
        }

        observeTitle()
        observeUnappliedWrites()
        observeRefreshInterval()
        observeAppearance()
        watchForChanges()
        scheduleUpdateChecks()
        // Without a token ThingsBar does nothing but ask for one: Things isn't read at all.
        if store.hasAuthToken { Task { await store.refresh() } }

        if let dir = SelfTest.outputDirectory {
            SelfTest.run(delegate: self, outputDirectory: dir)
        }
    }

    func makePanelView() -> some View {
        PanelView(store: store, state: panelState, tokenStore: tokenStore, updates: updates,
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

    /// Keeps the menu bar title in sync with the store via Observation. Text only: no icon, ever.
    private func observeTitle() {
        withObservationTracking {
            let title = store.hasAuthToken ? store.menuBarTitle : "ThingsBar"
            // Things unreachable: the (possibly stale) titles are dimmed, not decorated with an icon.
            let dimmed = store.hasAuthToken && store.thingsUnreachable
            if dimmed {
                statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: [
                    .font: NSFont.menuBarFont(ofSize: 0), .foregroundColor: NSColor.tertiaryLabelColor])
            } else {
                statusItem.button?.title = title // plain: keeps the menu bar's own text treatment
            }
            statusItem.button?.setAccessibilityLabel(dimmed ? "ThingsBar: Things can't be reached. \(title)" : "ThingsBar: \(title)")
            statusItem.button?.toolTip = !store.hasAuthToken ? TokenGate.prompt
                : store.errorMessage ?? store.visibleItems.prefix(5).map(\.title).joined(separator: "\n")
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTitle() }
        }
    }

    /// A URL-scheme write Things didn't apply usually means a token it no longer
    /// accepts: check the token, and if Things rejects it, go back to the token prompt.
    private func observeUnappliedWrites() {
        _ = withObservationTracking { store.unappliedWrites } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeUnappliedWrites()
                guard let token = self.tokenStore.token, case .invalid = await self.panelState.verifyToken(token) else { return }
                try? self.tokenStore.setToken(nil)
                self.panelState.gateMessage = TokenGate.revoked
                self.panelState.route = .list
                self.store.dismissError()
                self.store.hasAuthToken = false
            }
        }
    }

    /// Full refresh (catalog included) on the configured interval.
    private func observeRefreshInterval() {
        let seconds = withObservationTracking { store.settings.refreshSeconds } onChange: { [weak self] in
            Task { @MainActor in self?.observeRefreshInterval() }
        }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(seconds, 15)), repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let store = self?.store, store.hasAuthToken else { return }
                await store.refresh()
            }
        }
    }

    /// Things has no change notifications, so poll a cheap fingerprint every 2 s and
    /// refresh only when it differs (e.g. after reordering in Things).
    private func watchForChanges() {
        changeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let store = self?.store, store.hasAuthToken else { return }
                await store.checkForChanges()
            }
        }
        changeTimer?.tolerance = 0.5
    }

    /// At launch and every few hours, check GitHub if a day has passed since the last check.
    private func scheduleUpdateChecks() {
        guard !SelfTest.isActive else { return }
        let tick = { [weak self] in
            Task { @MainActor in
                guard let self, self.store.settings.checkForUpdatesAutomatically else { return }
                await self.updates.checkIfDue()
            }
        }
        tick()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { _ in tick() }
        updateTimer?.tolerance = 600
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
        guard store.hasAuthToken else {
            menu.addItem(withTitle: "Enter Things Auth Token…", action: #selector(openPanel), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit ThingsBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            return menu
        }
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
        if let release = updates.available {
            menu.addItem(withTitle: "Download ThingsBar \(release.version)…", action: #selector(downloadUpdate), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
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

    @objc private func downloadUpdate() { if let r = updates.available { UpdateActions.download(r) } }

    /// Shows the result where the button lives: Settings, inside the panel.
    @objc private func checkForUpdates() {
        openSettings()
        Task { await updates.check() }
    }

    @objc private func openPanel() { if !panel.isShown { showPanel() } }

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
        if store.hasAuthToken { Task { await store.refresh() } }
        button.highlight(true)
        if !SelfTest.isActive {
            panelState.opens = UserDefaults.standard.integer(forKey: "panelOpens") + 1
            UserDefaults.standard.set(panelState.opens, forKey: "panelOpens")
        }
        panel.show(below: button)
    }
}
