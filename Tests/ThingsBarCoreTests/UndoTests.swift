import Foundation
import Testing
@testable import ThingsBarCore

@MainActor
struct UndoTests {
    let items = ["a", "b", "c"].map { TodoItem(id: $0, title: $0.uppercased()) }

    func makeStore(_ source: ThingsSource = .today) async -> (TodoStore, InMemoryThingsClient) {
        let client = InMemoryThingsClient(items: [source: items])
        let settings = MemorySettings(); settings.stored.source = source
        let store = TodoStore(client: client, persistence: settings)
        store.hasAuthToken = true
        store.orderSyncDelay = .milliseconds(10)
        await store.refresh()
        return (store, client)
    }

    @Test func undoCompleteReopensInPlace() async {
        let (store, client) = await makeStore()
        await store.complete(store.items[1])
        #expect(store.undoAction?.label == "Completed \u{201C}B\u{201D}")
        #expect(store.items.map(\.id) == ["a", "c"])
        await store.undo()
        await store.waitForOrderSync()
        #expect(store.items.map(\.id) == ["a", "b", "c"])
        #expect(await client.log.contains("reopen b"))
        #expect(store.undoAction == nil)
    }

    @Test func undoCancelReopens() async {
        let (store, _) = await makeStore()
        await store.cancel(store.items[0])
        #expect(store.undoAction?.label.hasPrefix("Canceled") == true)
        await store.undo()
        #expect(store.items.map(\.id) == ["a", "b", "c"])
    }

    @Test func undoTrashRestoresAndPutsItBackInPlace() async {
        let (store, client) = await makeStore()
        await store.delete(store.items[2])
        #expect(store.undoAction?.label == "Moved \u{201C}C\u{201D} to Trash")
        await store.undo()            // restore puts it first in Things…
        await store.waitForOrderSync() // …then the old order is re-applied
        #expect(store.items.map(\.id) == ["a", "b", "c"])
        #expect(await client.items[ThingsSource.today.id]!.map(\.id) == ["a", "b", "c"])
    }

    @Test func undoReorderPutsTheOldOrderBack() async {
        let (store, client) = await makeStore()
        store.moveVisible(store.items[2], toGap: 0)
        store.moveVisible(store.items[2], toGap: 0) // a burst: c a b → b c a
        await store.waitForOrderSync()
        #expect(await client.items[ThingsSource.today.id]!.map(\.id) == ["b", "c", "a"])
        #expect(store.undoAction?.label == "Reordered")
        await store.undo()
        await store.waitForOrderSync()
        #expect(store.items.map(\.id) == ["a", "b", "c"], "undoes the whole burst")
        #expect(await client.items[ThingsSource.today.id]!.map(\.id) == ["a", "b", "c"])
    }

    @Test func undoExpires() async throws {
        let (store, _) = await makeStore()
        store.undoTimeout = .milliseconds(50)
        await store.complete(store.items[0])
        #expect(store.undoAction != nil)
        try await Task.sleep(for: .milliseconds(150))
        #expect(store.undoAction == nil)
    }

    @Test func trashInTagListOffersNoUndo() async {
        let tag = ThingsSource(kind: .tag, identifier: "Home", name: "Home")
        let (store, _) = await makeStore(tag)
        await store.delete(store.items[0])
        #expect(store.undoAction == nil, "a tag isn't a place to restore to")
    }

    @Test func failedActionOffersNoUndo() async {
        let (store, client) = await makeStore()
        await client.setFailNextCall(.changeNotApplied)
        await store.complete(store.items[0])
        #expect(store.undoAction == nil)
    }

    @Test func restoreTargets() {
        let project = ThingsSource(kind: .project, identifier: "p", name: "P")
        let now = Date()
        let plain = TodoItem(id: "x", title: "x")
        #expect(UndoSupport.restoreTarget(for: plain, from: .today) == .today)
        #expect(UndoSupport.restoreTarget(for: plain, from: .inbox) == .inbox)
        #expect(UndoSupport.restoreTarget(for: plain, from: .upcoming) == nil)
        #expect(UndoSupport.restoreTarget(for: plain, from: project) == .anytime)
        var today = plain; today.startDate = now
        #expect(UndoSupport.restoreTarget(for: today, from: project, now: now) == .today)
        var later = plain; later.startDate = now.addingTimeInterval(3 * 86_400)
        #expect(UndoSupport.restoreTarget(for: later, from: project, now: now) == nil, "a future date would be lost")
        #expect(UndoSupport.restoreTarget(for: plain, from: ThingsSource(kind: .tag, identifier: "t", name: "t")) == nil)
    }
}
