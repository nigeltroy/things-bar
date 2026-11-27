import Foundation
import Testing
@testable import ThingsBarCore

struct AppVersionTests {
    @Test func ordersReleases() {
        #expect(AppVersion.isNewer("0.5.0", than: "0.4.0"))
        #expect(AppVersion.isNewer("v0.4.1", than: "0.4.0"))
        #expect(AppVersion.isNewer("1.0", than: "0.9.9"))
        #expect(AppVersion.isNewer("0.10.0", than: "0.9.0"), "numeric, not lexical")
        #expect(!AppVersion.isNewer("0.4.0", than: "0.4.0"))
        #expect(!AppVersion.isNewer("0.3.0", than: "0.4.0"))
        #expect(AppVersion.compare("0.4", "0.4.0") == .orderedSame)
    }

    @Test func prereleasesAndBuildMetadata() {
        // CI builds of main are versioned "<base>-dev.<run>+<sha>".
        #expect(AppVersion.isNewer("0.4.0", than: "0.4.0-dev.12+abc1234"))
        #expect(!AppVersion.isNewer("0.4.0-dev.12", than: "0.4.0"))
        #expect(AppVersion.isNewer("0.4.0-dev.12", than: "0.4.0-dev.9"))
        #expect(AppVersion.compare("0.4.0+a", "0.4.0+b") == .orderedSame)
    }
}

struct ReleaseParsingTests {
    @Test func parsesGitHubLatest() throws {
        let json = """
        {"tag_name":"v0.5.0","html_url":"https://github.com/nigeltroy/things-bar/releases/tag/v0.5.0","draft":false,"prerelease":false,
         "assets":[{"name":"ThingsBar-0.5.0.dmg.sha256","browser_download_url":"https://example.com/a.sha256"},
                   {"name":"ThingsBar-0.5.0.dmg","browser_download_url":"https://example.com/a.dmg"}]}
        """
        let r = try ReleaseInfo.parse(githubLatest: Data(json.utf8))
        #expect(r.version == "0.5.0")
        #expect(r.downloadURL?.absoluteString == "https://example.com/a.dmg")
        #expect(r.pageURL.absoluteString.hasSuffix("/v0.5.0"))
    }

    @Test func rejectsPrerelease() {
        let json = #"{"tag_name":"v1.0.0-beta","html_url":"https://example.com","assets":[],"prerelease":true}"#
        #expect(throws: UpdateError.noRelease) { try ReleaseInfo.parse(githubLatest: Data(json.utf8)) }
    }
}

private struct StubFetcher: ReleaseFetching {
    let result: Result<ReleaseInfo, Error>
    func latestRelease() async throws -> ReleaseInfo { try result.get() }
}

@MainActor
struct UpdateCheckerTests {
    let page = URL(string: "https://example.com/r")!
    func defaults() -> UserDefaults { UserDefaults(suiteName: "thingsbar.tests.updates.\(UUID())")! }

    @Test func findsNewerRelease() async {
        let release = ReleaseInfo(version: "0.5.0", pageURL: page)
        let c = UpdateChecker(currentVersion: "0.4.0", fetcher: StubFetcher(result: .success(release)), defaults: defaults())
        #expect(await c.check() == .available(release))
        #expect(c.available == release)
        #expect(c.lastChecked != nil)
    }

    @Test func sameOrOlderIsUpToDate() async {
        for v in ["0.4.0", "0.3.0"] {
            let c = UpdateChecker(currentVersion: "0.4.0", fetcher: StubFetcher(result: .success(ReleaseInfo(version: v, pageURL: page))), defaults: defaults())
            #expect(await c.check() == .upToDate)
        }
    }

    @Test func manualFailureIsReportedAutomaticIsQuiet() async {
        let d = defaults()
        let c = UpdateChecker(currentVersion: "0.4.0", fetcher: StubFetcher(result: .failure(UpdateError.badResponse(503))), defaults: d)
        #expect(await c.check() == .failed("GitHub answered 503."))
        let auto = UpdateChecker(currentVersion: "0.4.0", fetcher: StubFetcher(result: .failure(UpdateError.badResponse(503))), defaults: defaults())
        await auto.checkIfDue()
        #expect(auto.status == .idle)
    }

    @Test func automaticCheckRunsAtMostDaily() async {
        let d = defaults()
        let release = ReleaseInfo(version: "0.5.0", pageURL: page)
        let c = UpdateChecker(currentVersion: "0.4.0", fetcher: StubFetcher(result: .success(release)), defaults: d)
        var clock = Date(timeIntervalSince1970: 1_000_000)
        c.now = { clock }
        await c.checkIfDue()
        #expect(c.available == release)
        // A fresh checker (next launch) within a day doesn't check again.
        let next = UpdateChecker(currentVersion: "0.4.0", fetcher: StubFetcher(result: .success(release)), defaults: d)
        clock += 3600
        next.now = { clock }
        await next.checkIfDue()
        #expect(next.status == .idle)
        clock += UpdateChecker.automaticInterval
        await next.checkIfDue()
        #expect(next.available == release)
    }
}

/// Opt-in: `THINGSBAR_NETWORK=1 swift test --filter LiveGitHub` reads the real latest release.
struct LiveGitHubReleaseTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["THINGSBAR_NETWORK"] == "1"))
    func latestReleaseIsReadable() async throws {
        let r = try await GitHubReleaseFetcher().latestRelease()
        #expect(!AppVersion.isNewer(ThingsBarInfo.version, than: r.version), "the app is never newer than its latest release")
        #expect(r.downloadURL?.lastPathComponent == "ThingsBar-\(r.version).dmg")
    }
}
