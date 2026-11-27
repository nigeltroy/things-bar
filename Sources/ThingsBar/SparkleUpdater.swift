import AppKit
import Observation
import Sparkle
import ThingsBarCore

/// What an in-place update is doing, shown in Settings and the panel footer.
@MainActor @Observable
final class InstallProgress {
    enum Phase: Equatable {
        case idle
        /// Reading the feed, then downloading and checking the signature.
        case downloading
        /// Quitting, replacing ThingsBar and reopening it.
        case installing
        case failed(String)
    }
    var phase: Phase = .idle { didSet { Self.log(phase) } }
    var isBusy: Bool { phase == .downloading || phase == .installing }

    /// Update tests read each phase from THINGSBAR_UPDATE_LOG.
    private static func log(_ phase: Phase) {
        guard let path = ProcessInfo.processInfo.environment["THINGSBAR_UPDATE_LOG"],
              let handle = FileHandle(forWritingAtPath: path) ?? {
                  FileManager.default.createFile(atPath: path, contents: nil); return FileHandle(forWritingAtPath: path)
              }() else { return }
        handle.seekToEndOfFile()
        handle.write(Data("\(phase)\n".utf8))
        try? handle.close()
    }
}

/// Installs updates in place with Sparkle, in one session: read the appcast, download
/// the DMG, check its EdDSA signature against SUPublicEDKey, then quit, replace
/// ThingsBar and reopen it. Choosing Install is the consent, so Sparkle shows no
/// windows of its own; progress shows in ThingsBar (`InstallProgress`).
///
/// ThingsBar's UpdateChecker still decides *when* to say an update exists, so Sparkle
/// never schedules checks (SUEnableAutomaticChecks is off). Silent downloads are
/// switched on only for the session Install starts (SUAllowsAutomaticUpdates permits it).
@MainActor
final class SparkleUpdater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    let progress = InstallProgress()
    /// The release Install was chosen for: opened in the browser if Sparkle's feed
    /// doesn't offer it (an older release without an appcast, or a feed problem).
    private var fallback: ReleaseInfo?
    private var installing = false

    /// Test hooks (`scripts/test-update.sh`): another feed, and install at launch.
    /// (The test copies set these in LSEnvironment, so the relaunched copy has them too.)
    private var feedOverride: String? { ProcessInfo.processInfo.environment["THINGSBAR_FEED_URL"] }
    /// An update test run: no Keychain, no Things, and Install runs at launch.
    static var isUpdateTest: Bool { ProcessInfo.processInfo.environment["THINGSBAR_UPDATE_TEST"] == "1" }

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        // Sparkle saves this setting; it must never outlive an Install.
        controller.updater.automaticallyDownloadsUpdates = false
        if Self.isUpdateTest { install(nil) } // the same path as the Install button
    }

    /// Sparkle can install only when the build carries the public key it verifies against.
    var isConfigured: Bool { Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil }

    /// Install the newest release in the feed; `release` is the browser fallback.
    func install(_ release: ReleaseInfo?) {
        guard isConfigured else { if let release { UpdateActions.openInBrowser(release) }; return }
        guard !progress.isBusy, !controller.updater.sessionInProgress else { return }
        fallback = release
        installing = true
        progress.phase = .downloading
        let updater = controller.updater
        updater.automaticallyDownloadsUpdates = true
        guard updater.automaticallyDownloadsUpdates else {
            // SUAllowsAutomaticUpdates missing: Sparkle would only notify. Use the browser.
            finish(failure: nil, openBrowser: true)
            return
        }
        updater.checkForUpdatesInBackground()
    }

    private func finish(failure: String?, openBrowser: Bool = false) {
        guard installing else { return }
        installing = false
        controller.updater.automaticallyDownloadsUpdates = false
        progress.phase = failure.map { .failed($0) } ?? .idle
        if openBrowser, let fallback { UpdateActions.openInBrowser(fallback) }
        fallback = nil
    }

    // MARK: SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? { feedOverride }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        // The feed doesn't have it (yet): download it the old way.
        finish(failure: nil, openBrowser: true)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        progress.phase = .installing
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        guard installing else { return false } // never install on quit behind the user's back
        progress.phase = .installing
        immediateInstallHandler() // quit, replace, reopen
        return true
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        finish(failure: "The download failed. \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        if (error as NSError).code == 1001 { return } // SUNoUpdateError: handled by updaterDidNotFindUpdate
        finish(failure: error.localizedDescription)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        // The session ended without installing (and nothing above explained why).
        guard installing, progress.phase != .installing else { return }
        finish(failure: error.map(\.localizedDescription) ?? "Sparkle stopped before installing.")
    }
}
