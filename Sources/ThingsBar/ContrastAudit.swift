import AppKit
import SwiftUI
import ThingsBarCore

/// Self-test contrast audit: renders every piece of text, every placeholder and every
/// meaningful glyph on its own, in dark and light, with and without Increase Contrast,
/// over a typical and a worst-case glass background, then measures the rendered
/// pixels. Measuring renders (not token values) catches styling that SwiftUI ignores,
/// such as a placeholder color that never applies.
///
/// The glass backgrounds are flat grays approximating Liquid Glass: offscreen renders
/// can't show the real thing. "worst" is glass over a backdrop that works against the
/// text (a bright window under dark glass, a dark one under light glass).
@MainActor
enum ContrastAudit {
    struct Sample {
        let name: String
        /// Text needs 4.5:1 (WCAG AA, small text); glyphs that carry meaning need 3:1.
        let isText: Bool
        let view: () -> AnyView
    }

    static let backgrounds: [(name: String, dark: CGFloat, light: CGFloat)] = [
        ("typical", 0.16, 0.92),
        ("worst", 0.30, 0.78),
    ]

    static func samples(_ store: TodoStore) -> [Sample] {
        let item = store.visibleItems.first ?? TodoItem(id: "x", title: "Sample to-do", tags: ["Home"], deadline: Date())
        func text(_ name: String, _ v: some View) -> Sample { Sample(name: name, isText: true) { AnyView(v) } }
        func glyph(_ name: String, _ v: some View) -> Sample { Sample(name: name, isText: false) { AnyView(v) } }
        let width = Theme.panelWidth - 2 * Theme.edgeInset
        return [
            // List page
            text("list title", Text("Today").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)),
            // Placeholders are measured in bare fields (same styling as in the app), so a
            // nearby glyph or button can't stand in for a faint placeholder.
            text("new to-do placeholder", TextField("", text: .constant(""), prompt: Text("")).placeholder("New To-Do", when: true)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.textPrimary).frame(width: 200)
                .padding(6).background(RoundedRectangle(cornerRadius: Theme.rowCorner).fill(Theme.fieldFill))),
            text("new to-do field (hints)", AddTodoField(store: store).frame(width: width)),
            text("new to-do typed text", AddTodoField(store: store, title: "Buy milk").frame(width: width)),
            text("row title", Text(item.title).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)),
            text("row project (meta)", Text("Website relaunch").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)),
            text("row #tags (meta)", Text("#Home #Office").font(.system(size: 11)).foregroundStyle(Theme.textMuted)),
            text("row deadline", Label("Tomorrow", systemImage: "flag.fill").font(.system(size: 11)).labelStyle(CompactLabelStyle()).foregroundStyle(Theme.textSecondary)),
            text("footer status", Text("Updated just now").font(.system(size: 11)).foregroundStyle(Theme.textMuted)),
            text("empty state", EmptyStateView(loading: false, filtered: false).frame(width: width)),
            text("error banner", ErrorBanner(message: "Couldn't reach Things.") {}.frame(width: width)),
            text("undo button", Button("Undo") {}.buttonStyle(SoftButtonStyle())),
            text("save button (prominent)", Button("Save") {}.buttonStyle(SoftButtonStyle(prominent: true))),
            text("save button (disabled)", Button("Save") {}.buttonStyle(SoftButtonStyle(prominent: true)).disabled(true)),
            glyph("checkbox ring", Checkbox(checked: false) {}),
            glyph("icon button glyph", IconButton(systemName: "gearshape", help: "Settings") {}),
            glyph("filter-on glyph", Image(systemName: "line.3.horizontal.decrease").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textTertiary)),
            glyph("empty-state check", Image(systemName: "checkmark").font(.system(size: 18)).foregroundStyle(Theme.textTertiary)),
            glyph("notes glyph", Image(systemName: "text.alignleft").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textMuted)),
            // Editor
            text("editor title placeholder", TextField("", text: .constant(""), prompt: Text("")).placeholder("Title", when: true)
                .textFieldStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary).frame(width: 200)),
            text("editor notes placeholder", TextField("", text: .constant(""), prompt: Text(""), axis: .vertical).placeholder("Notes", when: true)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).frame(width: 200)),
            text("editor notes typed", TextField("", text: .constant("Outline first"), axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).frame(width: 200)),
            text("editor deadline chip", Label("Deadline", systemImage: "flag").font(.system(size: 11)).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(Theme.strongFill))),
            text("editor tags chip", TagPicker(all: ["Home"], selection: .constant([]))),
            text("calendar weekday", Text("M").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textMuted)),
            // Settings
            text("section header", SectionHeader(title: "Menu bar").frame(width: 120)),
            text("settings row label", Text("Width").font(.system(size: 13)).foregroundStyle(Theme.textPrimary)),
            text("value chip", Text("Today").modifier(ValueChip())),
            text("contains placeholder", TextField("", text: .constant(""), prompt: Text("")).placeholder("Any text", when: true, alignment: .trailing)
                .textFieldStyle(.plain).font(.system(size: 12)).multilineTextAlignment(.trailing).frame(width: 130).modifier(ValueChip())),
            text("contains typed", TextField("", text: .constant("report"))
                .textFieldStyle(.plain).font(.system(size: 12)).multilineTextAlignment(.trailing).frame(width: 130).modifier(ValueChip())),
            text("note", Note(text: "Saved in your Keychain.").frame(width: width)),
            text("menu bar preview", PreviewLine(text: "Draft the quarterly planning doc").frame(width: width)),
            text("keyboard label", Text("Complete it").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)),
            text("keyboard keys", Text("Space").font(.system(size: 12)).foregroundStyle(Theme.textMuted)),
            text("filters summary", Text("Off").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)),
            // Token
            text("token prompt", Text(TokenGate.prompt).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)),
            text("token placeholder", SecureField("", text: .constant(""), prompt: Text("")).placeholder("Paste auth token", when: true)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textPrimary).frame(width: 200)
                .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(Theme.fieldFill))),
            text("token typed (dots)", SecureField("", text: .constant("abc123"))
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textPrimary).frame(width: 200)
                .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(Theme.fieldFill))),
            text("token field (whole)", TokenField(draft: .constant(""), savedToken: nil) {}.frame(width: width)),
        ]
    }

    /// Writes contrast.json and contrast-<theme>.png sheets; returns the failures.
    @discardableResult
    static func run(store: TodoStore, dir: URL) -> [String] {
        var rows: [[String: Any]] = []
        var failures: [String] = []
        for dark in [true, false] {
            for more in [false, true] {
                Theme.forceIncreaseContrast = more
                for bg in backgrounds {
                    let gray = dark ? bg.dark : bg.light
                    for sample in samples(store) {
                        guard let image = render(sample.view(), dark: dark, gray: gray) else { continue }
                        let ratio = measure(image, over: gray)
                        if ProcessInfo.processInfo.environment["THINGSBAR_AUDIT_DUMP"] != nil {
                            let file = "audit-\(dark ? "dark" : "light")\(more ? "-hc" : "")-\(bg.name)-\(sample.name.filter { $0.isLetter || $0.isNumber }).png"
                            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(file))
                        }
                        let needed = sample.isText ? 4.5 : 3.0
                        let pass = ratio >= needed
                        let label = "\(dark ? "dark" : "light")\(more ? "+contrast" : "") \(bg.name): \(sample.name)"
                        if !pass { failures.append("\(label) \(String(format: "%.2f", ratio)):1 < \(needed)") }
                        rows.append(["theme": dark ? "dark" : "light", "increaseContrast": more, "background": bg.name,
                                     "sample": sample.name, "kind": sample.isText ? "text" : "glyph",
                                     "ratio": (ratio * 100).rounded() / 100, "needed": needed, "pass": pass])
                    }
                }
            }
        }
        Theme.forceIncreaseContrast = false
        SelfTest.write(json: ["failures": failures, "results": rows], to: dir.appendingPathComponent("contrast.json"))
        return failures
    }

    /// Renders `view` at 2x over a flat gray.
    static func render(_ view: AnyView, dark: Bool, gray: CGFloat) -> CGImage? {
        let host = NSHostingView(rootView: view.padding(8).background(Color(white: gray)))
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
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.cgImage
    }

    /// Contrast between the most common color (the element's background) and the pixel
    /// that differs from it most (the core of the text or glyph).
    static func measure(_ image: CGImage, over gray: CGFloat) -> Double {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return 0 }
        // Fractional view sizes leave transparent edge pixels: fill them with the background.
        ctx.setFillColor(CGColor(gray: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var counts: [UInt32: Int] = [:]
        for i in stride(from: 0, to: data.count, by: 4) {
            let key = UInt32(data[i]) << 16 | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2])
            counts[key, default: 0] += 1
        }
        // Prefer the element's own fill when it has one: the most common color among
        // pixels away from the image edge.
        var inner: [UInt32: Int] = [:]
        let m = 18 // 9 pt at 2x: inside the 8 pt padding
        if w > 2 * m, h > 2 * m {
            for y in m..<(h - m) { for x in m..<(w - m) {
                let i = (y * w + x) * 4
                inner[UInt32(data[i]) << 16 | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]), default: 0] += 1
            } }
        }
        let bgKey = (inner.max { $0.value < $1.value } ?? counts.max { $0.value < $1.value })!.key
        let bgL = luminance(bgKey)
        var best = 1.0
        for (key, _) in counts {
            let l = luminance(key)
            best = max(best, (max(l, bgL) + 0.05) / (min(l, bgL) + 0.05))
        }
        return best
    }

    private static func luminance(_ key: UInt32) -> Double {
        func lin(_ c: UInt32) -> Double {
            let v = Double(c) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(key >> 16 & 0xff) + 0.7152 * lin(key >> 8 & 0xff) + 0.0722 * lin(key & 0xff)
    }
}
