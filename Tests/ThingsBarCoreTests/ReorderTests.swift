import Foundation
import Testing
@testable import ThingsBarCore

struct ReorderPlanTests {
    func permutations(_ a: [String]) -> [[String]] {
        guard a.count > 1 else { return [a] }
        return a.indices.flatMap { i -> [[String]] in
            var rest = a; let x = rest.remove(at: i)
            return permutations(rest).map { [x] + $0 }
        }
    }

    @Test func everyPermutationIsReachableWithFewestMoves() {
        let current = ["a", "b", "c", "d", "e"]
        for desired in permutations(current) {
            let moves = ReorderPlan.moveToTopSequence(from: current, to: desired)
            #expect(ReorderPlan.apply(moves, to: current) == desired, "\(desired)")
            // Fewest possible: no shorter set of top-moves can work, because the items
            // that stay must already be in order and form desired's tail.
            let keep = desired.count - moves.count
            for k in stride(from: keep + 1, through: desired.count, by: 1) {
                let tail = Array(desired.suffix(k))
                #expect(current.filter(tail.contains) != tail, "a longer kept tail exists for \(desired)")
            }
        }
    }

    @Test func typicalDrags() {
        let c = ["a", "b", "c", "d", "e"]
        #expect(ReorderPlan.moveToTopSequence(from: c, to: c).isEmpty)
        #expect(ReorderPlan.moveToTopSequence(from: c, to: ["e", "a", "b", "c", "d"]) == ["e"], "drag up = one move")
        #expect(ReorderPlan.moveToTopSequence(from: c, to: ["b", "c", "d", "e", "a"]) == ["e", "d", "c", "b"], "drag first to last")
        #expect(ReorderPlan.moveToTopSequence(from: c, to: ["b", "a", "c", "d", "e"]) == ["b"])
        #expect(ReorderPlan.moveToTopSequence(from: c, to: ["a", "c", "b", "d", "e"]) == ["c", "a"])
    }

    @Test func ignoresItemsThatAppearedOrVanished() {
        // "x" was added in Things and "c" completed while the user was dragging.
        let moves = ReorderPlan.moveToTopSequence(from: ["x", "a", "b", "c"], to: ["b", "a", "c"])
        #expect(moves == ["b"])
    }

    @Test func dropIntoVisibleListMapsToFullList() {
        let all = ["a", "h1", "b", "c", "h2", "d"] // h1, h2 hidden by a filter
        let visible = ["a", "b", "c", "d"]
        #expect(ReorderPlan.moveVisible(id: "d", toGap: 0, visible: visible, all: all) == ["d", "a", "h1", "b", "c", "h2"])
        #expect(ReorderPlan.moveVisible(id: "a", toGap: 4, visible: visible, all: all) == ["h1", "b", "c", "h2", "d", "a"])
        #expect(ReorderPlan.moveVisible(id: "a", toGap: 2, visible: visible, all: all) == ["h1", "b", "a", "c", "h2", "d"])
        #expect(ReorderPlan.moveVisible(id: "c", toGap: 1, visible: visible, all: all) == ["a", "h1", "c", "b", "h2", "d"])
        #expect(ReorderPlan.moveVisible(id: "b", toGap: 1, visible: visible, all: all) == nil, "dropped where it was")
        #expect(ReorderPlan.moveVisible(id: "b", toGap: 2, visible: visible, all: all) == nil, "dropped just below itself")
        #expect(ReorderPlan.moveVisible(id: "z", toGap: 0, visible: visible, all: all) == nil)
        #expect(ReorderPlan.moveVisible(id: "a", toGap: 9, visible: visible, all: all) == nil)
    }

    @Test func dropGapFollowsRowMiddles() {
        let mids: [Double] = [15, 45, 75, 105] // four 30 pt rows
        #expect(ReorderPlan.dropGap(pointerY: 2, rowMidYs: mids, from: 3) == 0)
        #expect(ReorderPlan.dropGap(pointerY: 50, rowMidYs: mids, from: 3) == 2)
        #expect(ReorderPlan.dropGap(pointerY: 200, rowMidYs: mids, from: 0) == 4, "below everything")
        #expect(ReorderPlan.dropGap(pointerY: 40, rowMidYs: mids, from: 1) == nil, "over itself: no move")
        #expect(ReorderPlan.dropGap(pointerY: 60, rowMidYs: mids, from: 1) == nil, "just below itself: no move")
        #expect(ReorderPlan.dropGap(pointerY: 80, rowMidYs: mids, from: 1) == 3)
    }

    @Test func supportedLists() {
        #expect(ReorderPlan.isSupported(in: .today))
        #expect(ReorderPlan.isSupported(in: .inbox))
        #expect(!ReorderPlan.isSupported(in: .anytime))
        #expect(!ReorderPlan.isSupported(in: ThingsSource(kind: .project, identifier: "p", name: "P")))
    }
}

@MainActor
struct StoreReorderTests {
    let items = ["a", "b", "c", "d"].map { TodoItem(id: $0, title: $0.uppercased(), tags: $0 == "b" ? ["Hidden"] : []) }

    func makeStore(source: ThingsSource = .today, token: Bool = true) async -> (TodoStore, InMemoryThingsClient) {
        let client = InMemoryThingsClient(items: [source: items])
        let settings = MemorySettings()
        settings.stored.source = source
        let store = TodoStore(client: client, persistence: settings)
        store.hasAuthToken = token
        store.orderSyncDelay = .milliseconds(20)
        await store.refresh()
        return (store, client)
    }

    @Test func dragUpdatesAtOnceThenSyncsToThings() async {
        let (store, client) = await makeStore()
        store.moveVisible(store.items[3], toGap: 0)
        #expect(store.items.map(\.id) == ["d", "a", "b", "c"], "optimistic")
        #expect(store.menuBarTitle == "D", "menu bar follows the drop immediately")
        await store.waitForOrderSync()
        #expect(await client.items[ThingsSource.today.id]!.map(\.id) == ["d", "a", "b", "c"])
        #expect(await client.log == ["top d"], "one move for a drag to the top")
        #expect(store.errorMessage == nil)
        #expect(store.orderJustSaved)
    }

    @Test func quickSuccessiveMovesSyncOnceWithFewestMoves() async {
        let (store, client) = await makeStore()
        store.orderSyncDelay = .milliseconds(200)
        store.moveVisible(store.items[0], toGap: 4)   // a to the bottom: b c d a
        store.moveVisible(store.items[0], toGap: 4)   // b to the bottom: c d a b
        await store.waitForOrderSync()
        #expect(await client.items[ThingsSource.today.id]!.map(\.id) == ["c", "d", "a", "b"])
        #expect(await client.log.filter { $0.hasPrefix("top") }.count == 2, "c d a b from a b c d needs two moves: d, c")
    }

    @Test func menuCommandsMoveByIndex() async {
        let (store, client) = await makeStore()
        store.moveVisible(store.items[1], to: 2) // Move Down
        #expect(store.items.map(\.id) == ["a", "c", "b", "d"])
        store.moveVisible(store.items[2], to: 0) // Move to Top
        #expect(store.items.map(\.id) == ["b", "a", "c", "d"])
        await store.waitForOrderSync()
        #expect(await client.items[ThingsSource.today.id]!.map(\.id) == ["b", "a", "c", "d"])
    }

    @Test func dragWithFilterKeepsHiddenItemsInPlace() async {
        let (store, client) = await makeStore()
        store.settings.filter.excludeTags = ["Hidden"]  // visible: a c d
        store.moveVisible(store.visibleItems[2], toGap: 0)
        #expect(store.visibleItems.map(\.id) == ["d", "a", "c"])
        await store.waitForOrderSync()
        #expect(await client.items[ThingsSource.today.id]!.map(\.id) == ["d", "a", "b", "c"])
    }

    @Test func failedSyncRollsBackAndExplains() async {
        let (store, client) = await makeStore()
        store.moveVisible(store.items[2], toGap: 0)
        await client.setFailNextCall(.changeNotApplied) // the fresh read before moving fails
        await store.waitForOrderSync()
        #expect(store.items.map(\.id) == ["a", "b", "c", "d"], "back to Things' order")
        #expect(store.errorMessage?.hasPrefix("Couldn't save the new order") == true)
    }

    @Test func refreshWhilePendingKeepsTheDroppedOrder() async {
        let (store, _) = await makeStore()
        store.orderSyncDelay = .milliseconds(300)
        store.moveVisible(store.items[3], toGap: 0)
        await store.refresh()
        #expect(store.items.map(\.id) == ["d", "a", "b", "c"])
        await store.checkForChanges()
        #expect(store.items.map(\.id) == ["d", "a", "b", "c"])
        await store.waitForOrderSync()
    }

    @Test func todayNeedsTokenInboxDoesNot() async {
        let (today, _) = await makeStore(token: false)
        #expect(!today.canReorder)
        #expect(today.reorderUnavailableReason?.contains("auth token") == true)
        today.moveVisible(today.items[3], toGap: 0)
        #expect(today.items.map(\.id) == ["a", "b", "c", "d"])

        let (inbox, client) = await makeStore(source: .inbox, token: false)
        #expect(inbox.canReorder)
        inbox.moveVisible(inbox.items[3], toGap: 0)
        await inbox.waitForOrderSync()
        #expect(await client.items[ThingsSource.inbox.id]!.map(\.id) == ["d", "a", "b", "c"])
    }

    @Test func otherListsCannotReorder() async {
        let (store, _) = await makeStore(source: .anytime)
        #expect(!store.canReorder)
        store.moveVisible(store.items[3], toGap: 0)
        #expect(store.items.map(\.id) == ["a", "b", "c", "d"])
    }
}
