import Foundation

/// User preferences (everything except the auth token, which lives in the Keychain).
public struct AppSettings: Codable, Equatable, Sendable {
    public var source: ThingsSource = .today
    public var filter = TodoFilter()
    /// How often to re-read Things while idle, in seconds.
    public var refreshSeconds: Int = 30
    /// Longest menu bar title before truncating with "…".
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

    public static func make(top: TodoItem?, remaining: Int, settings: AppSettings) -> String {
        guard let top else { return emptyTitle }
        var title = top.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = "Untitled" }
        let limit = max(settings.menuBarTitleLength, 4)
        if title.count > limit { title = String(title.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…" }
        if settings.showCountInMenuBar && remaining > 1 { title += "  +\(remaining - 1)" }
        return title
    }
}
