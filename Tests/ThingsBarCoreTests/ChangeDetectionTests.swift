import Foundation
import Testing
@testable import ThingsBarCore

/// Changes made in Things itself (reordering, edits) reach ThingsBar via `checkForChanges`.
@MainActor
struct ChangeDetectionTests {
    let a = TodoItem(id: "a", title: "First"), b = TodoItem(id: "b", title: "Second"), c = TodoItem(id: "c", title: "Third")

    @Test func reorderInThingsIsPickedUp() async {
        let client = InMemoryThingsClient(items: [.today: [a, b, c]])
        let store = TodoStore(client: client, persistence: MemorySettings())
        await store.refresh()
        #expect(store.menuBarTitle == "First")

        await client.setItems([c, a, b], for: .today) // user drags "Third" to the top in Things
        await store.checkForChanges()
        #expect(store.items.map(\.id) == ["c", "a", "b"])
        #expect(store.menuBarTitle == "Third")
    }

    @Test func editInThingsIsPickedUp() async {
        let client = InMemoryThingsClient(items: [.today: [a, b]])
        let store = TodoStore(client: client, persistence: MemorySettings())
        await store.refresh()
        var renamed = a; renamed.title = "First, renamed"
        await client.setItems([renamed, b], for: .today)
        await store.checkForChanges()
        #expect(store.topItem?.title == "First, renamed")
    }

    @Test func noChangeMeansNoRefresh() async {
        let client = InMemoryThingsClient(items: [.today: [a, b]])
        let store = TodoStore(client: client, persistence: MemorySettings())
        await store.refresh()
        let stamp = store.lastRefresh
        await store.checkForChanges()
        #expect(store.lastRefresh == stamp)
    }
}
