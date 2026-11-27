import Foundation

/// User preferences (everything except the auth token, which lives in the Keychain).
public struct AppSettings: Codable, Equatable, Sendable {
    public var source: ThingsSource = .today
    public var filter = TodoFilter()
    /// How often to re-read Things while idle, in seconds.
    public var refreshSeconds: Int = 30
    /// How many of the top to-dos the menu bar shows (1–3), separated by " | ".
    public var menuBarItemCount: Int = 1
    /// Room the menu bar title may take. Titles are truncated to fit by measured width,
    /// because macOS silently hides menu bar items that don't fit (e.g. by the notch).
    public var menuBarWidth: MenuBarWidth = .medium
    /// Character limit per to-do, used only when no text measurer is available.
    public var menuBarTitleLength: Int = 32
    /// Append the number of remaining to-dos, e.g. "Write report  +4".
    public var showCountInMenuBar = false
    public var appearance: Appearance = .dark
    /// Look for a newer ThingsBar on GitHub at most once a day.
    public var checkForUpdatesAutomatically = true

    public enum MenuBarWidth: String, Codable, CaseIterable, Sendable {
        case narrow, medium, wide
        public var points: Double { switch self { case .narrow: 160; case .medium: 240; case .wide: 360 } }
        public var label: String { rawValue.capitalized }
    }

    public enum Appearance: String, Codable, CaseIterable, Sendable {
        case system, dark, light
        public var label: String { rawValue.capitalized }
    }

    public init() {}

    // Tolerant decoding: new fields fall back to defaults instead of wiping settings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        source = try c.decodeIfPresent(ThingsSource.self, forKey: .source) ?? d.source
        filter = try c.decodeIfPresent(TodoFilter.self, forKey: .filter) ?? d.filter
        refreshSeconds = try c.decodeIfPresent(Int.self, forKey: .refreshSeconds) ?? d.refreshSeconds
        menuBarItemCount = try c.decodeIfPresent(Int.self, forKey: .menuBarItemCount) ?? d.menuBarItemCount
        menuBarWidth = try c.decodeIfPresent(MenuBarWidth.self, forKey: .menuBarWidth) ?? d.menuBarWidth
        menuBarTitleLength = try c.decodeIfPresent(Int.self, forKey: .menuBarTitleLength) ?? d.menuBarTitleLength
        showCountInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showCountInMenuBar) ?? d.showCountInMenuBar
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
        checkForUpdatesAutomatically = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdatesAutomatically) ?? d.checkForUpdatesAutomatically
    }
}

public protocol SettingsPersisting: Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

public final class UserDefaultsSettings: SettingsPersisting, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "settings.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    public func save(_ settings: AppSettings) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: key)
    }
}

/// Text shown in the menu bar.
public enum MenuBarTitle {
    public static let emptyTitle = "All clear"
    public static let separator = " | "

    /// The first `settings.menuBarItemCount` to-dos joined by " | ", plus "+N" for the rest
    /// when the count is on. With `measure` (text width in points, using the menu bar
    /// font), the whole title fits `settings.menuBarWidth`: short titles keep their full
    /// text and long ones share the remaining room. Without it, each title is cut at
    /// `settings.menuBarTitleLength` characters.
    public static func make(items: [TodoItem], settings: AppSettings,
                            measure: ((String) -> Double)? = nil) -> String {
        guard !items.isEmpty else { return emptyTitle }
        let shown = Array(items.prefix(min(max(settings.menuBarItemCount, 1), 3)))
        let titles = shown.map { item -> String in
            let t = item.title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
            return t.isEmpty ? "Untitled" : t
        }
        let rest = items.count - shown.count
        let suffix = settings.showCountInMenuBar && rest > 0 ? "  +\(rest)" : ""

        guard let measure else {
            let limit = max(settings.menuBarTitleLength, 4)
            return titles.map { truncate($0, toCharacters: limit) }.joined(separator: separator) + suffix
        }
        let budget = settings.menuBarWidth.points - measure(suffix) - Double(titles.count - 1) * measure(separator)
        let caps = fairShares(widths: titles.map(measure), budget: budget)
        return zip(titles, caps).map { truncate($0, toWidth: $1, measure: measure) }.joined(separator: separator) + suffix
    }

    /// Splits `budget` so items narrower than an equal share keep their width and the
    /// rest share what's left equally.
    static func fairShares(widths: [Double], budget: Double) -> [Double] {
        var caps = widths
        var remaining = max(budget, 0)
        var left = widths.count
        for i in widths.indices.sorted(by: { widths[$0] < widths[$1] }) {
            let share = remaining / Double(left)
            caps[i] = min(widths[i], share)
            remaining -= caps[i]
            left -= 1
        }
        return caps
    }

    static func truncate(_ s: String, toCharacters limit: Int) -> String {
        s.count > limit ? String(s.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…" : s
    }

    /// Longest prefix + "…" that fits `width` (at least one character).
    static func truncate(_ s: String, toWidth width: Double, measure: (String) -> Double) -> String {
        if measure(s) <= width + 0.5 { return s }
        var lo = 1, hi = s.count - 1, best = 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if measure(String(s.prefix(mid)).trimmingCharacters(in: .whitespaces) + "…") <= width { best = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return String(s.prefix(best)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
