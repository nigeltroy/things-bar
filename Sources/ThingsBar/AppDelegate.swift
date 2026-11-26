import AppKit
import SwiftUI
import ThingsBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "ThingsBar"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView())

        if let dir = SelfTest.outputDirectory {
            SelfTest.run(delegate: self, outputDirectory: dir)
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

struct PopoverView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ThingsBar \(ThingsBarInfo.version)")
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding()
        .frame(width: 320)
    }
}
