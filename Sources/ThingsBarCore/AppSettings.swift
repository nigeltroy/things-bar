import Foundation

/// User preferences (everything except the auth token, which lives in the Keychain).
public struct AppSettings: Codable, Equatable, Sendable {
    public var source: ThingsSource = .today
    public var filter = TodoFilter()
    /// How often to re-read Things while idle, in seconds.
    public var refreshSeconds: Int = 30
    /// How many of the top to-dos the menu bar shows (1–3), separated by " | ".
    public var menuBarItemCount: Int = 1
    /// Longest title per to-do in the menu bar before truncating with "…".
    public var menuBarTitleLength: Int = 32
    /// Append the number of remaining to-dos, e.g. "Write report  +4".
    public var showCountInMenuBar = false
    public var appearance: Appearance = .dark

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
        menuBarTitleLength = try c.decodeIfPresent(Int.self, forKey: .menuBarTitleLength) ?? d.menuBarTitleLength
        showCountInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showCountInMenuBar) ?? d.showCountInMenuBar
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
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

    /// The first `settings.menuBarItemCount` to-dos, each truncated, joined by " | ",
    /// plus "+N" for the rest when the count is turned on.
    public static func make(items: [TodoItem], settings: AppSettings) -> String {
        guard !items.isEmpty else { return emptyTitle }
        let shown = items.prefix(min(max(settings.menuBarItemCount, 1), 3))
        let limit = max(settings.menuBarTitleLength, 4)
        var title = shown.map { item in
            var t = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if t.isEmpty { t = "Untitled" }
            if t.count > limit { t = String(t.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…" }
            return t
        }.joined(separator: separator)
        let rest = items.count - shown.count
        if settings.showCountInMenuBar && rest > 0 { title += "  +\(rest)" }
        return title
    }
}
