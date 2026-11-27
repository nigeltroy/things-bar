import Foundation
import Testing
@testable import ThingsBarCore

final class MemorySettings: SettingsPersisting, @unchecked Sendable {
    var stored = AppSettings()
    var saves = 0
    func load() -> AppSettings { stored }
    func save(_ settings: AppSettings) { stored = settings; saves += 1 }
}

@MainActor
struct TodoStoreTests {
    let project = ThingsSource(kind: .project, identifier: "P1", name: "Work")

    func makeClient() -> InMemoryThingsClient {
        InMemoryThingsClient(
            catalog: SourceCatalog(projects: [project], tags: [ThingsSource(kind: .tag, identifier: "Home", name: "Home")]),
            items: [
                .today: [TodoItem(id: "a", title: "Write report", tags: ["Office"]),
                         TodoItem(id: "b", title: "Buy milk", tags: ["Home"])],
                project: [TodoItem(id: "c", title: "Ship v1")],
            ])
    }

    @Test func refreshLoadsCatalogAndTopItem() async {
        let store = TodoStore(client: makeClient(), persistence: MemorySettings())
        await store.refresh()
        #expect(store.items.map(\.id) == ["a", "b"])
        #expect(store.topItem?.title == "Write report")
        #expect(store.catalog.projects == [project])
        #expect(store.menuBarTitle == "Write report")
        #expect(store.errorMessage == nil)
    }

    @Test func filterChangesTopItem() async {
        let store = TodoStore(client: makeClient(), persistence: MemorySettings())
        await store.refresh()
        store.settings.filter.includeTags = ["Home"]
        #expect(store.topItem?.id == "b")
        store.settings.filter.includeTags = ["Nope"]
        #expect(store.topItem == nil)
        #expect(store.menuBarTitle == MenuBarTitle.emptyTitle)
    }

    @Test func changingSourcePersistsAndReloads() async throws {
        let persistence = MemorySettings()
        let store = TodoStore(client: makeClient(), persistence: persistence)
        await store.refresh()
        store.settings.source = project
        #expect(persistence.stored.source == project)
        await store.refresh()
        #expect(store.items.map(\.id) == ["c"])
        // A new store picks the saved source up.
        let again = TodoStore(client: makeClient(), persistence: persistence)
        #expect(again.settings.source == project)
    }

    @Test func errorsAreSurfacedAndCleared() async {
        let client = makeClient()
        let store = TodoStore(client: client, persistence: MemorySettings())
        await client.setFailNextCall(.automationDenied)
        await store.refresh()
        #expect(store.errorMessage == ThingsError.automationDenied.errorDescription)
        await store.refresh()
        #expect(store.errorMessage == nil)
    }

    @Test func menuBarTitleTruncatesAndCounts() {
        var s = AppSettings()
        s.menuBarTitleLength = 10
        let long = TodoItem(id: "x", title: "A very long to-do title")
        #expect(MenuBarTitle.make(items: [long], settings: s) == "A very lo…") // 10 characters including the ellipsis
        s.showCountInMenuBar = true
        let five = (1...5).map { TodoItem(id: "\($0)", title: $0 == 1 ? "Short" : "Item \($0)") }
        #expect(MenuBarTitle.make(items: five, settings: s) == "Short  +4")
        #expect(MenuBarTitle.make(items: [TodoItem(id: "y", title: "  ")], settings: s) == "Untitled")
    }

    @Test func settingsDecodeToleratesMissingFields() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"refreshSeconds": 99}"#.utf8))
        #expect(s.refreshSeconds == 99)
        #expect(s.source == .today)
    }
}

@MainActor
struct TodoStoreActionTests {
    func makeStore() -> (TodoStore, InMemoryThingsClient) {
        let client = InMemoryThingsClient(items: [.today: [
            TodoItem(id: "a", title: "First", notes: "n", tags: ["Home"]),
            TodoItem(id: "b", title: "Second"),
        ]])
        return (TodoStore(client: client, persistence: MemorySettings()), client)
    }

    @Test func addPutsNewItemOnTopAndTrims() async {
        let (store, client) = makeStore()
        await store.refresh()
        #expect(await store.add(TodoDraft(title: "  New one  ")))
        #expect(store.topItem?.title == "New one")
        #expect(await client.log == ["add New one"])
        #expect(await store.add(TodoDraft(title: "   ")) == false, "blank titles are ignored")
    }

    @Test func completeRemovesAndAdvancesTop() async {
        let (store, client) = makeStore()
        await store.refresh()
        await store.complete(store.topItem!)
        #expect(store.topItem?.id == "b")
        #expect(await client.log == ["complete a"])
        #expect(store.pendingIDs.isEmpty)
    }

    @Test func failedDeleteRestoresRowAndShowsError() async {
        let (store, client) = makeStore()
        await store.refresh()
        await client.setFailNextCall(.timedOut)
        await store.delete(store.items[0])
        #expect(store.items.map(\.id) == ["a", "b"])
        #expect(store.errorMessage == ThingsError.timedOut.errorDescription)
    }

    @Test func updateSendsOnlyRealChanges() async {
        let (store, client) = makeStore()
        await store.refresh()
        let item = store.items[0]
        #expect(await store.update(item, changes: TodoChanges(title: "First", notes: "n", tags: ["Home"])))
        #expect(await client.log.isEmpty, "no-op edit sends nothing")
        #expect(await store.update(item, changes: TodoChanges(title: "Renamed", notes: "n")))
        #expect(await client.log == ["update a"])
        #expect(store.items[0].title == "Renamed")
    }

    @Test func minimizedComparesDeadlinesByDay() {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.date(from: DateComponents(year: 2026, month: 12, day: 5, hour: 0))!
        let sameDayLater = cal.date(byAdding: .hour, value: 9, to: day)!
        let item = TodoItem(id: "x", title: "t", deadline: day)
        #expect(TodoChanges(deadline: .some(sameDayLater)).minimized(against: item, calendar: cal).isEmpty)
        #expect(!TodoChanges(deadline: .some(nil)).minimized(against: item, calendar: cal).isEmpty)
        #expect(TodoChanges(deadline: .some(nil)).minimized(against: TodoItem(id: "y", title: "t"), calendar: cal).isEmpty)
    }


    @Test func menuBarShowsTopOneToThreeItems() {
        var s = AppSettings()
        let items = ["Write report", "Buy milk", "Call mum", "Water plants"].enumerated()
            .map { TodoItem(id: "\($0.offset)", title: $0.element) }
        #expect(MenuBarTitle.make(items: items, settings: s) == "Write report")
        s.menuBarItemCount = 2
        #expect(MenuBarTitle.make(items: items, settings: s) == "Write report | Buy milk")
        s.menuBarItemCount = 3
        #expect(MenuBarTitle.make(items: items, settings: s) == "Write report | Buy milk | Call mum")
        s.showCountInMenuBar = true
        #expect(MenuBarTitle.make(items: items, settings: s) == "Write report | Buy milk | Call mum  +1")
        #expect(MenuBarTitle.make(items: Array(items.prefix(2)), settings: s) == "Write report | Buy milk", "fewer to-dos than slots")
        s.menuBarTitleLength = 6 // truncation applies per to-do
        #expect(MenuBarTitle.make(items: Array(items.prefix(2)), settings: s) == "Write… | Buy m…")
        s.menuBarItemCount = 9 // clamped to 3
        s.showCountInMenuBar = false
        #expect(MenuBarTitle.make(items: items, settings: s).components(separatedBy: " | ").count == 3)
        #expect(MenuBarTitle.make(items: [TodoItem(id: "n", title: "Line one\nline two")], settings: AppSettings()) == "Line one line two")
    }

    @Test func oldSettingsDecodeWithItemCountDefault() throws {
        let old = #"{"menuBarTitleLength":20,"showCountInMenuBar":true}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(AppSettings.self, from: old)
        #expect(s.menuBarItemCount == 1)
        #expect(s.menuBarTitleLength == 20)
    }

    @Test func menuBarFitsByMeasuredWidth() {
        let measure: (String) -> Double = { Double($0.count) * 6 } // fake 6 pt per character
        var s = AppSettings()
        s.menuBarWidth = .narrow // 160 pt
        let long = TodoItem(id: "l", title: String(repeating: "x", count: 60))
        let fit = MenuBarTitle.make(items: [long], settings: s, measure: measure)
        #expect(measure(fit) <= 160 && fit.hasSuffix("…"))
        #expect(fit.count == 26, "fills the room: 25 characters + …")

        // Three to-dos: short ones keep their full text, the long one takes the rest.
        s.menuBarItemCount = 3
        let items = [TodoItem(id: "a", title: "Gym"), long, TodoItem(id: "c", title: "Call mum")]
        let three = MenuBarTitle.make(items: items, settings: s, measure: measure)
        #expect(three.hasPrefix("Gym | x") && three.hasSuffix("… | Call mum"))
        #expect(measure(three) <= 160)

        // The "+N" count is part of the budget.
        s.showCountInMenuBar = true
        let counted = MenuBarTitle.make(items: items + [TodoItem(id: "d", title: "d")], settings: s, measure: measure)
        #expect(counted.hasSuffix("  +1") && measure(counted) <= 160)

        // Wide fits everything that is short enough.
        s.menuBarWidth = .wide
        s.showCountInMenuBar = false
        let short = [TodoItem(id: "a", title: "Write report"), TodoItem(id: "b", title: "Buy milk")]
        #expect(MenuBarTitle.make(items: short, settings: s, measure: measure) == "Write report | Buy milk")
    }

    @Test func fairSharesGiveShortItemsTheirWidth() {
        #expect(MenuBarTitle.fairShares(widths: [10, 100, 20], budget: 90) == [10, 60, 20])
        #expect(MenuBarTitle.fairShares(widths: [100, 100], budget: 90) == [45, 45])
        #expect(MenuBarTitle.fairShares(widths: [10, 20], budget: 90) == [10, 20])
    }

    @Test func menuBarSaysThingsBarBeforeFirstRead() async {
        let client = InMemoryThingsClient(items: [.today: [TodoItem(id: "a", title: "Write report")]])
        let store = TodoStore(client: client, persistence: MemorySettings())
        #expect(store.menuBarTitle == "ThingsBar")
        await store.refresh()
        #expect(store.menuBarTitle == "Write report")
    }
}
