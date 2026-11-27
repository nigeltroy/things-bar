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
        #expect(MenuBarTitle.make(top: long, remaining: 1, settings: s) == "A very lo…") // 10 characters including the ellipsis
        s.showCountInMenuBar = true
        #expect(MenuBarTitle.make(top: TodoItem(id: "y", title: "Short"), remaining: 5, settings: s) == "Short  +4")
        #expect(MenuBarTitle.make(top: TodoItem(id: "y", title: "  "), remaining: 1, settings: s) == "Untitled")
    }

    @Test func settingsDecodeToleratesMissingFields() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"refreshSeconds": 99}"#.utf8))
        #expect(s.refreshSeconds == 99)
        #expect(s.source == .today)
    }
}
