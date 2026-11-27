import Foundation
import Testing
@testable import ThingsBarCore

/// Completed to-dos stay under the open ones, checked, so a mistake is one click to undo.
@MainActor
struct CompletedTests {
    let items = ["a", "b", "c"].map { TodoItem(id: $0, title: $0.uppercased(), tags: $0 == "b" ? ["work"] : []) }

    func makeStore(_ source: ThingsSource = .today) async -> (TodoStore, InMemoryThingsClient) {
        let client = InMemoryThingsClient(items: [source: items, .inbox: [TodoItem(id: "x", title: "X")]])
        let settings = MemorySettings(); settings.stored.source = source
        let store = TodoStore(client: client, persistence: settings)
        store.hasAuthToken = true
        store.orderSyncDelay = .milliseconds(10)
        await store.refresh()
        return (store, client)
    }

    @Test func completedMovesToTheBottomAndStaysAfterRefresh() async {
        let (store, client) = await makeStore()
        await store.complete(store.items[0])
        await store.complete(store.items[0])
        #expect(store.visibleItems.map(\.id) == ["c"])
        #expect(store.visibleCompleted.map(\.id) == ["a", "b"], "in the order they were completed")
        #expect(await client.log.contains("complete a"))
        await store.refresh()
        #expect(store.visibleCompleted.map(\.id) == ["a", "b"])
        #expect(store.menuBarTitle.contains("C") && !store.menuBarTitle.contains("A"), "the menu bar shows open to-dos only")
    }

    @Test func reopeningPutsItBackWhereItWas() async {
        let (store, client) = await makeStore()
        await store.complete(store.items[1])
        await store.reopenCompleted(store.visibleCompleted[0])
        await store.waitForOrderSync()
        #expect(store.items.map(\.id) == ["a", "b", "c"])
        #expect(store.visibleCompleted.isEmpty)
        #expect(store.undoAction == nil, "nothing left to undo")
        #expect(await client.log.contains("reopen b"))
    }

    @Test func undoAlsoClearsTheCompletedRow() async {
        let (store, _) = await makeStore()
        await store.complete(store.items[2])
        await store.undo()
        #expect(store.visibleCompleted.isEmpty)
        #expect(store.items.map(\.id) == ["a", "b", "c"])
    }

    @Test func failedCompletionLeavesNoCompletedRow() async {
        let (store, client) = await makeStore()
        await client.setFailNextCall(.changeNotApplied)
        await store.complete(store.items[0])
        #expect(store.visibleCompleted.isEmpty)
        #expect(store.items.map(\.id) == ["a", "b", "c"])
    }

    @Test func reopenedInThingsDropsOut() async {
        let (store, client) = await makeStore()
        await store.complete(store.items[0])
        try? await client.reopen(id: "a") // the user reopened it in Things
        await store.refresh()
        #expect(store.visibleCompleted.isEmpty)
        #expect(store.items.map(\.id).contains("a"))
    }

    @Test func changingTheSourceClearsCompleted() async {
        let (store, _) = await makeStore()
        await store.complete(store.items[0])
        store.settings.source = .inbox
        #expect(store.visibleCompleted.isEmpty)
    }

    @Test func filtersApplyToCompletedToo() async {
        let (store, _) = await makeStore()
        await store.complete(store.items[0])
        await store.complete(store.items[0]) // b, tagged work
        store.settings.filter.excludeTags = ["work"]
        #expect(store.visibleCompleted.map(\.id) == ["a"])
    }

    @Test func cancelDoesNotKeepARow() async {
        let (store, _) = await makeStore()
        await store.cancel(store.items[0])
        #expect(store.visibleCompleted.isEmpty)
    }
}
