import Foundation

public enum ThingsBarInfo {
    public static let version = "0.6.2"
}

/// An open to-do as read from Things.
public struct TodoItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var notes: String
    public var tags: [String]
    /// Things' "deadline" (AppleScript `due date`).
    public var deadline: Date?
    /// Things' start date (AppleScript `activation date`), e.g. set by "when".
    public var startDate: Date?
    public var projectID: String?
    public var areaID: String?

    public init(id: String, title: String, notes: String = "", tags: [String] = [],
                deadline: Date? = nil, startDate: Date? = nil, projectID: String? = nil, areaID: String? = nil) {
        self.id = id; self.title = title; self.notes = notes; self.tags = tags
        self.deadline = deadline; self.startDate = startDate; self.projectID = projectID; self.areaID = areaID
    }
}

/// A place to-dos can be listed from: a built-in list, a project, an area or a tag.
public struct ThingsSource: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case list, project, area, tag }

    public var kind: Kind
    /// Things ID for lists/projects/areas; the tag's name for tags.
    public var identifier: String
    public var name: String

    public var id: String { "\(kind.rawValue):\(identifier)" }

    public init(kind: Kind, identifier: String, name: String) {
        self.kind = kind; self.identifier = identifier; self.name = name
    }

    // Built-in list IDs as reported by Things' AppleScript `id of list` (locale independent).
    public static let inbox = ThingsSource(kind: .list, identifier: "TMInboxListSource", name: "Inbox")
    public static let today = ThingsSource(kind: .list, identifier: "TMTodayListSource", name: "Today")
    public static let anytime = ThingsSource(kind: .list, identifier: "TMNextListSource", name: "Anytime")
    public static let upcoming = ThingsSource(kind: .list, identifier: "TMCalendarListSource", name: "Upcoming")
    public static let someday = ThingsSource(kind: .list, identifier: "TMSomedayListSource", name: "Someday")
    public static let builtInLists: [ThingsSource] = [.inbox, .today, .anytime, .upcoming, .someday]
}

/// Everything the user can pick as a source, plus lookups for display.
public struct SourceCatalog: Sendable, Equatable {
    public var lists: [ThingsSource]
    public var projects: [ThingsSource]
    public var areas: [ThingsSource]
    public var tags: [ThingsSource]

    public init(lists: [ThingsSource] = ThingsSource.builtInLists, projects: [ThingsSource] = [],
                areas: [ThingsSource] = [], tags: [ThingsSource] = []) {
        self.lists = lists; self.projects = projects; self.areas = areas; self.tags = tags
    }

    public var tagNames: [String] { tags.map(\.name) }

    public func projectName(for id: String?) -> String? {
        guard let id else { return nil }
        return projects.first { $0.identifier == id }?.name
    }

    public func areaName(for id: String?) -> String? {
        guard let id else { return nil }
        return areas.first { $0.identifier == id }?.name
    }
}

/// Fields for a new to-do.
public struct TodoDraft: Sendable, Equatable {
    public var title: String
    public var notes: String = ""
    public var tags: [String] = []
    public var deadline: Date?
    public init(title: String, notes: String = "", tags: [String] = [], deadline: Date? = nil) {
        self.title = title; self.notes = notes; self.tags = tags; self.deadline = deadline
    }
}

/// When to schedule a to-do (Things' "when").
public enum WhenOption: String, CaseIterable, Sendable, Codable {
    case today, evening, tomorrow, anytime, someday
    public var label: String {
        switch self {
        case .today: "Today"
        case .evening: "This Evening"
        case .tomorrow: "Tomorrow"
        case .anytime: "Anytime"
        case .someday: "Someday"
        }
    }
}

/// Edits to an existing to-do. `nil` means "leave unchanged".
public struct TodoChanges: Sendable, Equatable {
    public var title: String?
    public var notes: String?
    public var tags: [String]?
    /// `.some(nil)` clears the deadline.
    public var deadline: Date??
    public var when: WhenOption?

    public init(title: String? = nil, notes: String? = nil, tags: [String]? = nil,
                deadline: Date?? = nil, when: WhenOption? = nil) {
        self.title = title; self.notes = notes; self.tags = tags; self.deadline = deadline; self.when = when
    }

    public var isEmpty: Bool { title == nil && notes == nil && tags == nil && deadline == nil && when == nil }
}
