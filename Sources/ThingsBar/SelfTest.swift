import AppKit
import SwiftUI

/// Launch with `--selftest <dir>`: the app reports on itself and quits.
/// Writes status.json (status item state) and PNG renders of its own views,
/// so the UI can be verified without Accessibility or Screen Recording access.
@MainActor
enum SelfTest {
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
            let report: [String: Any] = [
                "isVisible": item.isVisible,
                "title": item.button?.title ?? "",
                "buttonWindowFrame": NSStringFromRect(frame),
            ]
            write(json: report, to: dir.appendingPathComponent("status.json"))
            snapshot(PopoverView(), to: dir.appendingPathComponent("popover.png"))
            NSApp.terminate(nil)
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
