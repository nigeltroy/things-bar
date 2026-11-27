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
            write(json: report, to: dir.appendingPathComponent("status.json"))
            renderViews(delegate, dir)

            var steps: [[String: Any]] = []
            if !useLiveThings {
                steps = await fixtureActions(delegate)
            } else if runActions {
                steps = await liveActions(delegate)
            }
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
        snapshot(PopoverView(store: store), to: dir.appendingPathComponent("popover.png"))
        snapshot(PopoverView(store: store), to: dir.appendingPathComponent("popover-light.png"), dark: false)
        snapshot(SettingsView(store: store, tokenStore: d.tokenStore), to: dir.appendingPathComponent("settings.png"))
        if let first = store.visibleItems.first {
            snapshot(TodoEditor(store: store, item: first) {}.padding(6).frame(width: 360).background(Theme.background),
                     to: dir.appendingPathComponent("editor.png"))
        }
        snapshot(ErrorBanner(message: ThingsError.changeNotApplied.errorDescription!) {}.padding(12).frame(width: 360)
            .background(Theme.background), to: dir.appendingPathComponent("error.png"))
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
        out.append(await step("filter Home", d) { s.settings.filter.includeTags = ["Home"]; return true })
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
