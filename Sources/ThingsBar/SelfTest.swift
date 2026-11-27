import AppKit
import SwiftUI
import ThingsBarCore

/// Launch with `--selftest <dir>`: the app exercises itself, writes reports and
/// PNG renders of its own views into <dir>, then quits. Needs no Accessibility or
/// Screen Recording permission.
///
///   --selftest-live           use the real Things instead of fixture data
///   --selftest-source <name>  built-in list to read in live mode (e.g. Anytime)
///   --selftest-actions        live mode: add/edit/complete/cancel/delete test to-dos
///                             (token from THINGS_AUTH_TOKEN; items prefixed "tbapp-")
@MainActor
enum SelfTest {
    static let args = CommandLine.arguments
    static var isActive: Bool { args.contains("--selftest") }
    static var useLiveThings: Bool { args.contains("--selftest-live") }
    static var runActions: Bool { args.contains("--selftest-actions") }

    static var outputDirectory: URL? {
        guard let i = args.firstIndex(of: "--selftest"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func makeStore(tokenStore: TokenStoring) -> TodoStore {
        if useLiveThings {
            try? tokenStore.setToken(ProcessInfo.processInfo.environment["THINGS_AUTH_TOKEN"])
            let store = AppDelegate.makeLiveStore(tokenStore: tokenStore, persistence: ephemeralSettings())
            if let i = args.firstIndex(of: "--selftest-source"), i + 1 < args.count,
               let source = ThingsSource.builtInLists.first(where: { $0.name == args[i + 1] }) {
                store.settings.source = source
            }
            return store
        }
        try? tokenStore.setToken("fixture-token")
        let work = ThingsSource(kind: .project, identifier: "P1", name: "Website relaunch")
        let cal = Calendar.current
        let client = InMemoryThingsClient(
            catalog: SourceCatalog(projects: [work], tags: ["Home", "Office", "Errand"].map { ThingsSource(kind: .tag, identifier: $0, name: $0) }),
            items: [.today: [
                TodoItem(id: "1", title: "Draft the quarterly planning doc", notes: "Outline first", tags: ["Office"],
                         deadline: cal.date(byAdding: .day, value: 1, to: Date()), projectID: "P1"),
                TodoItem(id: "2", title: "Book dentist appointment", tags: ["Home"]),
                TodoItem(id: "3", title: "Review pull requests", projectID: "P1"),
                TodoItem(id: "4", title: "Pick up dry cleaning", tags: ["Errand"],
                         deadline: cal.date(byAdding: .day, value: -2, to: Date())),
            ]])
        return TodoStore(client: client, persistence: ephemeralSettings())
    }

    /// No network in self-tests: a pretend newer release, so the update UI can be checked.
    static func makeUpdateChecker() -> UpdateChecker {
        struct Fixed: ReleaseFetching {
            func latestRelease() async throws -> ReleaseInfo {
                ReleaseInfo(version: "9.9.0", pageURL: URL(string: "https://github.com/nigeltroy/things-bar/releases")!)
            }
        }
        return UpdateChecker(fetcher: Fixed(), defaults: UserDefaults(suiteName: "thingsbar.selftest.\(UUID())")!)
    }

    /// Throwaway settings so a self-test never touches real preferences.
    static func ephemeralSettings() -> SettingsPersisting {
        UserDefaultsSettings(defaults: UserDefaults(suiteName: "thingsbar.selftest.\(UUID())")!)
    }

    static func run(delegate: AppDelegate, outputDirectory dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task {
            try? await Task.sleep(for: .seconds(1.5)) // let the status item settle and the first refresh land
            await store(delegate).refresh()
            var report = statusReport(delegate)
            report["quickMenu"] = delegate.makeQuickMenu().items.map { $0.isSeparatorItem ? "---" : $0.title }
            report["rowHeights"] = hoverHeights(delegate)
            report["statusItemHasImage"] = delegate.statusItem.button?.image != nil
            write(json: report, to: dir.appendingPathComponent("status.json"))
            renderViews(delegate, dir)
            ContrastAudit.run(store: store(delegate), dir: dir) // writes contrast.json

            var steps: [[String: Any]] = []
            if !useLiveThings {
                steps = await fixtureActions(delegate)
            } else if runActions {
                steps = await liveActions(delegate)
            }
            if !useLiveThings { renderUpdates(delegate, dir, "updates-available") }
            write(json: ["steps": steps], to: dir.appendingPathComponent("actions.json"))
            NSApp.terminate(nil)
        }
    }

    private static func store(_ d: AppDelegate) -> TodoStore { d.store }

    static func statusReport(_ d: AppDelegate) -> [String: Any] {
        let item = d.statusItem!
        return [
            "isVisible": item.isVisible,
            "title": item.button?.title ?? "",
            "buttonWindowFrame": NSStringFromRect(item.button?.window?.frame ?? .zero),
            "source": d.store.settings.source.name,
            "itemCount": d.store.visibleItems.count,
            "items": d.store.visibleItems.map(\.title),
            "error": d.store.errorMessage ?? NSNull(),
        ]
    }

    static func renderViews(_ d: AppDelegate, _ dir: URL) {
        let store = d.store!
        func panel(_ route: PanelState.Route) -> some View {
            let state = PanelState(); state.route = route
            return PanelView(store: store, state: state, tokenStore: d.tokenStore, updates: d.updates)
        }
        snapshot(GlassPreview { panel(.list) }, to: dir.appendingPathComponent("panel.png"))
        snapshot(GlassPreview { panel(.list) }, to: dir.appendingPathComponent("panel-light.png"), dark: false)
        if store.visibleItems.count >= 3 {
            let dragged = store.visibleItems[2].id
            snapshot(GlassPreview {
                TodoListView(store: store, state: PanelState(), previewDrag: (dragged, 0)).frame(width: Theme.panelWidth)
            }, to: dir.appendingPathComponent("drag.png"))
        }
        snapshot(GlassPreview { panel(.settings) }, to: dir.appendingPathComponent("settings.png"))
        snapshot(GlassPreview { panel(.settings) }, to: dir.appendingPathComponent("settings-light.png"), dark: false)
        Theme.forceIncreaseContrast = true
        snapshot(GlassPreview { panel(.list) }, to: dir.appendingPathComponent("panel-contrast.png"))
        snapshot(GlassPreview { panel(.list) }, to: dir.appendingPathComponent("panel-contrast-light.png"), dark: false)
        Theme.forceIncreaseContrast = false
        if let first = store.visibleItems.first {
            snapshot(GlassPreview {
                VStack(spacing: 0) {
                    TodoRow(store: store, item: first, edit: {}, forceHover: true)
                    ForEach(store.visibleItems.dropFirst().prefix(2)) { TodoRow(store: store, item: $0, edit: {}) }
                }.padding(Theme.edgeInset).frame(width: Theme.panelWidth)
            }, to: dir.appendingPathComponent("hover.png"))
            snapshot(GlassPreview {
                TodoEditor(store: store, item: first) {}.padding(Theme.edgeInset).frame(width: Theme.panelWidth)
            }, to: dir.appendingPathComponent("editor.png"))
            if let plain = store.visibleItems.first(where: { $0.notes.isEmpty }) {
                for (name, dark) in [("editor-empty-notes.png", true), ("editor-empty-notes-light.png", false)] {
                    snapshot(GlassPreview {
                        TodoEditor(store: store, item: plain) {}.padding(Theme.edgeInset).frame(width: Theme.panelWidth)
                    }, to: dir.appendingPathComponent(name), dark: dark)
                }
            }
        }
        renderUpdates(d, dir, "updates-idle")
        // No token: the panel is only the token prompt.
        let gateStore = TodoStore(client: InMemoryThingsClient(), persistence: ephemeralSettings())
        for (name, dark) in [("gate.png", true), ("gate-light.png", false)] {
            snapshot(GlassPreview { PanelView(store: gateStore, state: PanelState(), tokenStore: MemoryTokenStore()) },
                     to: dir.appendingPathComponent(name), dark: dark)
        }
        snapshot(GlassPreview {
            ErrorBanner(message: ThingsError.changeNotApplied.errorDescription!) {}.padding(Theme.edgeInset).frame(width: Theme.panelWidth)
        }, to: dir.appendingPathComponent("error.png"))
    }

    /// The Settings update rows and the list footer, in dark and light.
    static func renderUpdates(_ d: AppDelegate, _ dir: URL, _ name: String) {
        for dark in [true, false] {
            snapshot(GlassPreview {
                VStack(spacing: 0) {
                    UpdateRows(updates: d.updates, automatic: .constant(true))
                    Rectangle().fill(Theme.separator).frame(height: 1).padding(.horizontal, Theme.textInset)
                    // A fresh store, so no undo toast or status outranks the update note.
                    HStack { FooterStatus(store: TodoStore(client: InMemoryThingsClient(), persistence: ephemeralSettings()),
                                          state: PanelState(), updates: d.updates); Spacer() }
                        .padding(.horizontal, Theme.textInset).padding(.vertical, 6)
                }.padding(Theme.edgeInset).frame(width: Theme.panelWidth)
            }, to: dir.appendingPathComponent(name + (dark ? ".png" : "-light.png")), dark: dark)
        }
    }

    /// Row height with and without hover, for every visible row: hovering must not resize rows.
    static func hoverHeights(_ d: AppDelegate) -> [[String: Any]] {
        let store = d.store!
        var out: [[String: Any]] = []
        for item in store.visibleItems {
            var h: [CGFloat] = []
            for hover in [false, true] {
                h.append(NSHostingView(rootView: TodoRow(store: store, item: item, edit: {}, forceHover: hover)
                    .frame(width: Theme.panelWidth - 2 * Theme.edgeInset)).fittingSize.height)
            }
            out.append(["title": item.title, "normal": h[0], "hover": h[1]])
        }
        return out
    }

    /// Runs one step and records what the menu bar showed afterwards.
    private static func step(_ name: String, _ d: AppDelegate, _ body: () async -> Bool) async -> [String: Any] {
        let ok = await body()
        try? await Task.sleep(for: .milliseconds(100)) // let observation update the button
        return ["step": name, "ok": ok, "menuBarTitle": d.statusItem.button?.title ?? "",
                "items": d.store.visibleItems.map(\.title), "error": d.store.errorMessage ?? NSNull()]
    }

    static func fixtureActions(_ d: AppDelegate) async -> [[String: Any]] {
        let s = d.store!
        var out: [[String: Any]] = []
        out.append(await step("add", d) { await s.add(TodoDraft(title: "Water the plants")) })
        out.append(await step("complete top", d) { await s.complete(s.topItem!); return true })
        out.append(await step("edit", d) {
            await s.update(s.items[0], changes: TodoChanges(title: "Draft the Q1 planning doc"))
        })
        out.append(await step("delete", d) { await s.delete(s.items.last!); return true })
        out.append(await step("menu bar shows top 3", d) {
            s.settings.menuBarItemCount = 3
            try? await Task.sleep(for: .milliseconds(50))
            let title = d.statusItem.button?.title ?? ""
            return title.components(separatedBy: " | ").count == 3 && d.statusItem.button?.image == nil
        })
        out.append(await step("menu bar back to 1", d) {
            s.settings.menuBarItemCount = 1
            try? await Task.sleep(for: .milliseconds(50))
            return !(d.statusItem.button?.title ?? "").contains(" | ")
        })
        out.append(contentsOf: await panelSteps(d))
        out.append(await step("filter Home", d) { s.settings.filter.includeTags = ["Home"]; return true })
        out.append(await step("update check finds a newer release", d) {
            let before = d.makeQuickMenu().items.map(\.title)
            await d.updates.check()
            let after = d.makeQuickMenu().items.map(\.title)
            return before.contains("Check for Updates…") && d.updates.available?.version == "9.9.0"
                && after.contains("Download ThingsBar 9.9.0…")
        })
        out.append(contentsOf: await tokenGateSteps(d))
        return out
    }

    /// Without a token the app only asks for one: plain "ThingsBar" in the menu bar, a
    /// quick menu with nothing but the token prompt and Quit, no list keys.
    static func tokenGateSteps(_ d: AppDelegate) async -> [[String: Any]] {
        let s = d.store!
        var out: [[String: Any]] = []
        out.append(await step("no token: only the token prompt", d) {
            try? d.tokenStore.setToken(nil)
            s.hasAuthToken = false
            try? await Task.sleep(for: .milliseconds(50))
            let menu = d.makeQuickMenu().items.map { $0.isSeparatorItem ? "---" : $0.title }
            let keys = ListKeys.handle(keyCode: 125, modifiers: [], store: s, state: d.panelState)
            d.showPanel(); try? await Task.sleep(for: .milliseconds(300))
            let panelHeight = d.panel.panel.frame.height
            d.panel.close()
            NSLog("gate: menu %@, keys handled %d, panel height %.0f", menu.description, keys ? 1 : 0, panelHeight)
            return d.statusItem.button?.title == "ThingsBar" && d.statusItem.button?.image == nil
                && menu == ["Enter Things Auth Token…", "---", "Quit ThingsBar"] && !keys && panelHeight < 200
        })
        out.append(await step("token saved: the list is back", d) {
            try? d.tokenStore.setToken("fixture-token")
            s.hasAuthToken = true
            await s.refresh()
            try? await Task.sleep(for: .milliseconds(50))
            return d.statusItem.button?.title != "ThingsBar" && !s.visibleItems.isEmpty
        })
        return out
    }

    /// Opens the real panel and checks placement, glass, settings navigation and Esc.
    static func panelSteps(_ d: AppDelegate) async -> [[String: Any]] {
        let pc = d.panel!, panel = d.panel.panel
        func settle() async { try? await Task.sleep(for: .milliseconds(400)) }
        func info() -> [String: Any] {
            let b = d.statusItem.button!
            let br = b.window!.convertToScreen(b.convert(b.bounds, to: nil))
            return ["panelFrame": NSStringFromRect(panel.frame), "buttonFrame": NSStringFromRect(br),
                    "gapBelowButton": br.minY - panel.frame.maxY, "visible": panel.isVisible, "key": panel.isKeyWindow,
                    "glass": String(describing: type(of: panel.contentView!)), "route": "\(d.panelState.route)"]
        }
        var out: [[String: Any]] = []
        d.showPanel(); await settle()
        var listInfo = info()
        let listHeight = panel.frame.height, listTop = panel.frame.maxY
        listInfo["step"] = "open panel"
        listInfo["ok"] = panel.isVisible && panel.isKeyWindow && abs((listInfo["gapBelowButton"] as! CGFloat) - PanelController.gapBelowMenuBar) < 1
            && (listInfo["glass"] as! String).contains("Glass") && panel.frame.width == Theme.panelWidth
        out.append(listInfo)

        d.panelState.route = .settings; await settle()
        var settingsInfo = info()
        settingsInfo["step"] = "settings in same panel"
        settingsInfo["ok"] = panel.isVisible && abs(panel.frame.maxY - listTop) < 1 && panel.frame.height != listHeight
        out.append(settingsInfo)

        panel.cancelOperation(nil); await settle() // Esc
        var back = info(); back["step"] = "esc goes back"; back["ok"] = d.panelState.route == .list && panel.isVisible
        out.append(back)

        panel.cancelOperation(nil); await settle() // Esc again
        var closed = info(); closed["step"] = "esc closes"; closed["ok"] = !panel.isVisible && !pc.isShown
        out.append(closed)

        d.openSettings(); await settle()
        var quick = info(); quick["step"] = "quick menu Settings… opens panel on settings"
        quick["ok"] = panel.isVisible && d.panelState.route == .settings
        out.append(quick)
        pc.close(); await settle()
        return out
    }

    /// End-to-end against the real Things, through the same store the UI uses.
    static func liveActions(_ d: AppDelegate) async -> [[String: Any]] {
        let s = d.store!
        s.settings.source = .today
        await s.refresh()
        let tag = "tbapp-\(UUID().uuidString.prefix(6))"
        func find(_ title: String) -> TodoItem? { s.items.first { $0.title == title } }
        var out: [[String: Any]] = []

        out.append(await step("add", d) { await s.add(TodoDraft(title: "\(tag) one", notes: "from app")) })
        out.append(await step("edit title+deadline", d) {
            guard let item = find("\(tag) one") else { return false }
            return await s.update(item, changes: TodoChanges(title: "\(tag) one edited", deadline: .some(Date())))
        })
        out.append(await step("schedule evening", d) {
            guard let item = find("\(tag) one edited") else { return false }
            return await s.update(item, changes: TodoChanges(when: .evening))
        })
        out.append(await step("complete", d) {
            guard let item = find("\(tag) one edited") else { return false }
            await s.complete(item)
            return find(item.title) == nil
        })
        out.append(await step("add two", d) { await s.add(TodoDraft(title: "\(tag) two")) })
        out.append(await step("cancel", d) {
            guard let item = find("\(tag) two") else { return false }
            await s.cancel(item)
            return find(item.title) == nil
        })
        out.append(await step("add three", d) { await s.add(TodoDraft(title: "\(tag) three")) })
        out.append(await step("delete", d) {
            guard let item = find("\(tag) three") else { return false }
            await s.delete(item)
            return find(item.title) == nil
        })
        // A reorder made outside ThingsBar (as if dragged in Things) must reach the menu
        // bar through the app's own change polling, with no explicit refresh.
        out.append(await step("add four, five", d) {
            let a = await s.add(TodoDraft(title: "\(tag) four"))
            let b = await s.add(TodoDraft(title: "\(tag) five"))
            return a && b && s.topItem?.title == "\(tag) five"
        })
        out.append(await step("external reorder shows up", d) {
            guard let four = find("\(tag) four") else { return false }
            do { try await s.client.moveToTop(id: four.id, in: .today) } catch { return false }
            try? await Task.sleep(for: .seconds(3)) // change polling runs every 2 s
            return s.topItem?.title == "\(tag) four" && d.statusItem.button?.title.contains("\(tag) four") == true
        })
        out.append(await step("drag five above four syncs to Things", d) {
            guard let five = find("\(tag) five"), let from = s.visibleItems.firstIndex(of: five),
                  let four = s.visibleItems.firstIndex(where: { $0.title == "\(tag) four" }) else { return false }
            _ = from
            s.moveVisible(five, toGap: four)          // what dropping on the line above "four" does
            try? await Task.sleep(for: .milliseconds(50)) // the title updates on the next run-loop turn
            let optimistic = d.statusItem.button?.title.contains("\(tag) five") == true
            await s.waitForOrderSync()
            let things = (try? await s.client.todos(in: .today).map(\.title)) ?? []
            let checks = ["optimistic": optimistic, "thingsOrder": things.prefix(2) == ["\(tag) five", "\(tag) four"],
                          "noError": s.errorMessage == nil, "top": s.topItem?.title == "\(tag) five"]
            if checks.values.contains(false) { NSLog("drag checks: %@ things: %@", checks.description, things.description) }
            return !checks.values.contains(false)
        })
        for title in ["\(tag) four", "\(tag) five"] { if let item = find(title) { await s.delete(item) } }
        out.append(["tag": tag])
        return out
    }

    static func write(json: [String: Any], to url: URL) {
        let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: url)
    }

    /// Renders a SwiftUI view in an offscreen, layer-backed window to PNG, over an
    /// opaque backdrop so transparent areas are visible.
    static func snapshot<V: View>(_ view: V, to url: URL, dark: Bool = true) {
        let host = NSHostingView(rootView: view)
        host.wantsLayer = true
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        host.display()
        defer { window.orderOut(nil) }

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let content = rep.cgImage else { return }
        let ctx = CGContext(data: nil, width: content.width, height: content.height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let full = CGRect(x: 0, y: 0, width: content.width, height: content.height)
        ctx.setFillColor(dark ? CGColor(gray: 0.12, alpha: 1) : CGColor(gray: 1, alpha: 1))
        ctx.fill(full)
        ctx.draw(content, in: full)
        guard let out = ctx.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Offscreen renders can't show real Liquid Glass (the window server composites it),
/// so self-test images approximate it: a busy wallpaper under a translucent panel.
struct GlassPreview<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: Theme.panelCorner)
                .fill(scheme == .dark ? Color(white: 0.12).opacity(0.70) : Color(white: 0.98).opacity(0.68)))
            .overlay(RoundedRectangle(cornerRadius: Theme.panelCorner).strokeBorder(Color.white.opacity(scheme == .dark ? 0.12 : 0.5)))
            .padding(24)
            .background(LinearGradient(colors: scheme == .dark
                ? [Color(red: 0.16, green: 0.22, blue: 0.36), Color(red: 0.42, green: 0.20, blue: 0.30), Color(red: 0.10, green: 0.30, blue: 0.28)]
                : [Color(red: 0.60, green: 0.75, blue: 0.95), Color(red: 0.98, green: 0.78, blue: 0.70), Color(red: 0.70, green: 0.92, blue: 0.80)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
