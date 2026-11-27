import Foundation

/// User-configurable filters applied on top of the chosen source.
public struct TodoFilter: Codable, Hashable, Sendable {
    /// If non-empty, keep only to-dos with at least one of these tags.
    public var includeTags: [String] = []
    /// Drop to-dos with any of these tags.
    public var excludeTags: [String] = []
    /// Keep only to-dos that have a deadline.
    public var onlyWithDeadline = false
    /// Drop to-dos whose start date is after today (scheduled for later).
    public var hideScheduledLater = false
    /// Case-insensitive match on title or notes.
    public var searchText = ""

    public init(includeTags: [String] = [], excludeTags: [String] = [], onlyWithDeadline: Bool = false,
                hideScheduledLater: Bool = false, searchText: String = "") {
        self.includeTags = includeTags; self.excludeTags = excludeTags
        self.onlyWithDeadline = onlyWithDeadline; self.hideScheduledLater = hideScheduledLater
        self.searchText = searchText
    }

    public var isActive: Bool { self != TodoFilter() }

    /// Filters while preserving Things' order (which mirrors the Things UI).
    public func apply(to items: [TodoItem], now: Date = Date(), calendar: Calendar = .current) -> [TodoItem] {
        let include = Set(includeTags.map { $0.lowercased() })
        let exclude = Set(excludeTags.map { $0.lowercased() })
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!

        return items.filter { item in
            let tags = Set(item.tags.map { $0.lowercased() })
            if !include.isEmpty && tags.isDisjoint(with: include) { return false }
            if !tags.isDisjoint(with: exclude) { return false }
            if onlyWithDeadline && item.deadline == nil { return false }
            if hideScheduledLater, let start = item.startDate, start >= startOfTomorrow { return false }
            if !query.isEmpty,
               !item.title.localizedCaseInsensitiveContains(query),
               !item.notes.localizedCaseInsensitiveContains(query) { return false }
            return true
        }
    }
}
