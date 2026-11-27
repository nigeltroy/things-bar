import AppKit
import Sparkle
import ThingsBarCore

/// Installs updates in place with Sparkle: download, check the EdDSA signature against
/// SUPublicEDKey, quit, replace ThingsBar and reopen it, with Sparkle's standard windows
/// for progress.
///
/// ThingsBar's own UpdateChecker still decides *when* to say an update exists (the
/// quiet footer note, Settings, the quick menu), so Sparkle never schedules checks or
/// asks for permission to (SUEnableAutomaticChecks is off). Sparkle only runs when you
/// choose Install.
@MainActor
final class SparkleUpdater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    /// The release Install was chosen for: opened in the browser if Sparkle's feed
    /// doesn't offer it (an older release without an appcast, or a feed problem).
    private var pending: ReleaseInfo?
    private var probing = false

    /// Test hooks (`scripts/test-update.sh`): another feed, and install without asking.
    /// (The test copies set these in LSEnvironment, so the relaunched copy has them too.)
    private var feedOverride: String? { ProcessInfo.processInfo.environment["THINGSBAR_FEED_URL"] }
    private var installsWithoutAsking: Bool { Self.isUpdateTest }
    /// An update test run: no Keychain, no Things, install without asking.
    static var isUpdateTest: Bool { ProcessInfo.processInfo.environment["THINGSBAR_UPDATE_TEST"] == "1" }

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        if installsWithoutAsking {
            controller.updater.automaticallyDownloadsUpdates = true
            controller.updater.checkForUpdatesInBackground()
        }
    }

    /// Sparkle can install only when the build carries the public key it verifies against.
    var isConfigured: Bool { Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil }

    /// Install `release`: first a silent look at the feed, then Sparkle's install window
    /// if the feed has it, or the browser download if not.
    func install(_ release: ReleaseInfo) {
        guard isConfigured else { UpdateActions.openInBrowser(release); return }
        pending = release
        probing = true
        controller.updater.checkForUpdateInformation()
    }

    // MARK: SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? { feedOverride }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard probing else { return }
        probing = false
        // A background app: bring Sparkle's window to the front.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) { feedFailed() }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) { feedFailed() }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        guard installsWithoutAsking else { return false }
        immediateInstallHandler() // quit, replace, relaunch
        return true
    }

    private func feedFailed() {
        guard probing else { return }
        probing = false
        if let release = pending { UpdateActions.openInBrowser(release) }
        pending = nil
    }
}
