import AppKit
import ThingsBarCore

/// Opens things:/// URLs. Background writes don't steal focus from the user.
struct WorkspaceURLOpener: URLOpening {
    func open(_ url: URL, activate: Bool) async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = activate
        config.addsToRecentItems = false
        guard let thingsApp = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            throw ThingsError.thingsNotInstalled
        }
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: thingsApp, configuration: config)
    }

    func launchThings() async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ThingsAppleEventTransport.bundleID) else {
            throw ThingsError.thingsNotInstalled
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        try await Task.sleep(for: .seconds(1)) // let Things finish launching before scripting it
    }
}
