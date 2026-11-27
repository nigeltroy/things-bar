import AppKit
import SwiftUI
import ThingsBarCore

/// Launch with `--selftest <dir>`: the app reports on itself and quits.
/// Writes status.json (status item state) and PNG renders of its own views,
/// so the UI can be verified without Accessibility or Screen Recording access.
@MainActor
enum SelfTest {
    static var isActive: Bool { CommandLine.arguments.contains("--selftest") }
    /// `--selftest-live` reads the real Things instead of fixture data.
    static var useLiveThings: Bool { CommandLine.arguments.contains("--selftest-live") }

    static func makeStore(tokenStore: TokenStoring) -> TodoStore {
        if useLiveThings {
            let store = AppDelegate.makeLiveStore(tokenStore: tokenStore, persistence: ephemeralSettings())
            // `--selftest-source <built-in list name>` e.g. Anytime
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--selftest-source"), i + 1 < args.count,
               let source = ThingsSource.builtInLists.first(where: { $0.name == args[i + 1] }) {
                store.settings.source = source
            }
            return store
        }
        let work = ThingsSource(kind: .project, identifier: "P1", name: "Work")
        let client = InMemoryThingsClient(
            catalog: SourceCatalog(projects: [work], tags: [ThingsSource(kind: .tag, identifier: "Home", name: "Home")]),
            items: [.today: [
                TodoItem(id: "1", title: "Draft the quarterly planning doc", tags: ["Office"], projectID: "P1"),
                TodoItem(id: "2", title: "Book dentist appointment", tags: ["Home"]),
                TodoItem(id: "3", title: "Review pull requests", projectID: "P1"),
            ]])
        return TodoStore(client: client, persistence: ephemeralSettings())
    }

    /// Throwaway settings so a self-test never touches real preferences.
    static func ephemeralSettings() -> SettingsPersisting {
        UserDefaultsSettings(defaults: UserDefaults(suiteName: "thingsbar.selftest.\(UUID())")!)
    }

    static var outputDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func run(delegate: AppDelegate, outputDirectory dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Give AppKit a moment to place the status item.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let item = delegate.statusItem!
            let frame = item.button?.window?.frame ?? .zero
            let store = delegate.store!
            let report: [String: Any] = [
                "isVisible": item.isVisible,
                "title": item.button?.title ?? "",
                "buttonWindowFrame": NSStringFromRect(frame),
                "source": store.settings.source.name,
                "itemCount": store.visibleItems.count,
                "items": store.visibleItems.map(\.title),
                "error": store.errorMessage ?? NSNull(),
            ]
            write(json: report, to: dir.appendingPathComponent("status.json"))
            snapshot(PopoverView(store: store), to: dir.appendingPathComponent("popover.png"))
            snapshot(SettingsView(store: store, tokenStore: delegate.tokenStore), to: dir.appendingPathComponent("settings.png"))

            // Exercise settings → store → menu bar wiring.
            if !useLiveThings {
                store.settings.filter.includeTags = ["Home"]
                store.settings.showCountInMenuBar = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                write(json: ["titleAfterFilter": item.button?.title ?? "",
                             "visibleAfterFilter": store.visibleItems.map(\.title)],
                      to: dir.appendingPathComponent("after-settings.json"))
                NSApp.terminate(nil)
            }
        }
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
