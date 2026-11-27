import Foundation
import Testing
@testable import ThingsBarCore

struct TodoFilterTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 15))! }

    var items: [TodoItem] {
        [
            TodoItem(id: "1", title: "Buy milk", tags: ["Errand"]),
            TodoItem(id: "2", title: "Write report", notes: "Q4 numbers", tags: ["Office", "Important"],
                     deadline: now),
            TodoItem(id: "3", title: "Call mom", tags: ["Home"],
                     startDate: cal.date(byAdding: .day, value: 3, to: now)),
            TodoItem(id: "4", title: "Plan trip", startDate: cal.startOfDay(for: now)),
        ]
    }

    @Test func emptyFilterKeepsEverythingInOrder() {
        #expect(TodoFilter().apply(to: items, now: now, calendar: cal).map(\.id) == ["1", "2", "3", "4"])
        #expect(!TodoFilter().isActive)
    }

    @Test func includeTagsIsAnyOfAndCaseInsensitive() {
        let f = TodoFilter(includeTags: ["office", "HOME"])
        #expect(f.apply(to: items, now: now, calendar: cal).map(\.id) == ["2", "3"])
    }

    @Test func excludeTagsWins() {
        let f = TodoFilter(includeTags: ["Office"], excludeTags: ["Important"])
        #expect(f.apply(to: items, now: now, calendar: cal).isEmpty)
    }

    @Test func onlyWithDeadline() {
        #expect(TodoFilter(onlyWithDeadline: true).apply(to: items, now: now, calendar: cal).map(\.id) == ["2"])
    }

    @Test func hideScheduledLaterKeepsTodayStarts() {
        let ids = TodoFilter(hideScheduledLater: true).apply(to: items, now: now, calendar: cal).map(\.id)
        #expect(ids == ["1", "2", "4"])
    }

    @Test func searchMatchesTitleAndNotes() {
        #expect(TodoFilter(searchText: "q4").apply(to: items, now: now, calendar: cal).map(\.id) == ["2"])
        #expect(TodoFilter(searchText: "  MILK ").apply(to: items, now: now, calendar: cal).map(\.id) == ["1"])
    }

    @Test func filterRoundTripsThroughJSON() throws {
        let f = TodoFilter(includeTags: ["A"], excludeTags: ["B"], onlyWithDeadline: true, hideScheduledLater: true, searchText: "x")
        let back = try JSONDecoder().decode(TodoFilter.self, from: JSONEncoder().encode(f))
        #expect(back == f)
    }
}
