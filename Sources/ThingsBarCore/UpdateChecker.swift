import Foundation
import Observation

/// A published ThingsBar release.
public struct ReleaseInfo: Equatable, Sendable {
    public var version: String
    /// The release's GitHub page.
    public var pageURL: URL
    /// The DMG, if the release has one.
    public var downloadURL: URL?

    public init(version: String, pageURL: URL, downloadURL: URL? = nil) {
        self.version = version; self.pageURL = pageURL; self.downloadURL = downloadURL
    }

    /// Parses GitHub's `GET /repos/{owner}/{repo}/releases/latest` response.
    /// Drafts and prereleases are ignored (the endpoint skips them too).
    public static func parse(githubLatest data: Data) throws -> ReleaseInfo {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Release: Decodable {
            let tag_name: String; let html_url: URL; let assets: [Asset]
            let draft: Bool?; let prerelease: Bool?
        }
        let r = try JSONDecoder().decode(Release.self, from: data)
        guard r.draft != true, r.prerelease != true else { throw UpdateError.noRelease }
        let version = r.tag_name.hasPrefix("v") ? String(r.tag_name.dropFirst()) : r.tag_name
        let dmg = r.assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browser_download_url
        return ReleaseInfo(version: version, pageURL: r.html_url, downloadURL: dmg)
    }
}

public enum UpdateError: LocalizedError, Equatable {
    case noRelease
    case badResponse(Int)

    public var errorDescription: String? {
        switch self {
        case .noRelease: "No release found."
        case .badResponse(let code): "GitHub answered \(code)."
        }
    }
}

/// Semantic-version ordering for "1.2.3", "v1.2.3" and CI builds like
/// "0.4.0-dev.12+abc1234". A prerelease sorts below its release; build metadata is ignored.
public enum AppVersion {
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let (ac, ap) = split(a), (bc, bp) = split(b)
        for i in 0..<max(ac.count, bc.count) {
            let x = i < ac.count ? ac[i] : 0, y = i < bc.count ? bc[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        switch (ap, bp) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending // 1.0.0 > 1.0.0-dev.1
        case (_, nil): return .orderedAscending
        case let (x?, y?): return x == y ? .orderedSame : (x.compare(y, options: .numeric) == .orderedAscending ? .orderedAscending : .orderedDescending)
        }
    }

    private static func split(_ v: String) -> (core: [Int], pre: String?) {
        var s = v.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        if let plus = s.firstIndex(of: "+") { s = String(s[..<plus]) }
        let parts = s.split(separator: "-", maxSplits: 1).map(String.init)
        let core = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
        return (core, parts.count > 1 ? parts[1] : nil)
    }
}

/// Fetches the latest release. Abstracted so tests never touch the network.
public protocol ReleaseFetching: Sendable {
    func latestRelease() async throws -> ReleaseInfo
}

public struct GitHubReleaseFetcher: ReleaseFetching {
    public static let latestURL = URL(string: "https://api.github.com/repos/nigeltroy/things-bar/releases/latest")!
    let url: URL
    public init(url: URL = GitHubReleaseFetcher.latestURL) { self.url = url }

    public func latestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ThingsBar/\(ThingsBarInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw UpdateError.noRelease }
        guard code == 200 else { throw UpdateError.badResponse(code) }
        return try ReleaseInfo.parse(githubLatest: data)
    }
}

/// Checks for a newer ThingsBar: on demand, and at most once a day automatically.
@MainActor @Observable
public final class UpdateChecker {
    public enum Status: Equatable, Sendable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case failed(String)
    }

    public private(set) var status: Status = .idle
    public private(set) var lastChecked: Date?
    public let currentVersion: String

    @ObservationIgnored private let fetcher: ReleaseFetching
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored public var now: () -> Date = Date.init
    public static let automaticInterval: TimeInterval = 24 * 60 * 60
    private static let lastCheckedKey = "updates.lastChecked"

    public init(currentVersion: String = ThingsBarInfo.version, fetcher: ReleaseFetching = GitHubReleaseFetcher(),
                defaults: UserDefaults = .standard) {
        self.currentVersion = currentVersion
        self.fetcher = fetcher
        self.defaults = defaults
        lastChecked = defaults.object(forKey: Self.lastCheckedKey) as? Date
    }

    /// The newer release, if one was found.
    public var available: ReleaseInfo? {
        if case .available(let r) = status { return r }
        return nil
    }

    /// Checks now. Returns the new status.
    @discardableResult
    public func check() async -> Status {
        if status == .checking { return status }
        status = .checking
        do {
            let latest = try await fetcher.latestRelease()
            status = AppVersion.isNewer(latest.version, than: currentVersion) ? .available(latest) : .upToDate
        } catch UpdateError.noRelease {
            status = .upToDate
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        lastChecked = now()
        defaults.set(lastChecked, forKey: Self.lastCheckedKey)
        return status
    }

    /// Automatic check: only if the last one was more than a day ago. Failures stay
    /// quiet (status goes back to idle) so a flaky network never nags.
    public func checkIfDue() async {
        if let last = lastChecked, now().timeIntervalSince(last) < Self.automaticInterval { return }
        if case .failed = await check() { status = .idle }
    }
}
