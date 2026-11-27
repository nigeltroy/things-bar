import Foundation
import Testing
@testable import ThingsBarCore

/// Talks to the real Things 3. Opt-in:
///   THINGSBAR_INTEGRATION=1 THINGS_AUTH_TOKEN=… swift test --filter LiveThings
/// Creates uniquely named to-dos and moves them to Things' Trash afterwards.
private let enabled = ProcessInfo.processInfo.environment["THINGSBAR_INTEGRATION"] == "1"
private let token = ProcessInfo.processInfo.environment["THINGS_AUTH_TOKEN"]

/// `open -g` launches the URL without bringing Things forward.
struct ShellOpener: URLOpening {
    func open(_ url: URL, activate: Bool) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = (activate ? [] : ["-g"]) + [url.absoluteString]
        try p.run()
        p.waitUntilExit()
    }

    func launchThings() async throws {
        try await open(URL(string: "things:///version")!, activate: false)
        try await Task.sleep(for: .seconds(1))
    }
}

@Suite(.enabled(if: enabled), .serialized, .timeLimit(.minutes(1)))
struct LiveThingsIntegrationTests {
    let client = LiveThingsClient(opener: ShellOpener(), authToken: { token })
    let tag = "tbtest-\(UUID().uuidString.prefix(8))"

    func find(_ title: String, in source: ThingsSource = .today) async throws -> TodoItem? {
        try await client.todos(in: source).first { $0.title == title }
    }

    @Test func catalogListsProjectsAndTags() async throws {
        let catalog = try await client.catalog()
        #expect(!catalog.tags.isEmpty)
        #expect(catalog.projects.allSatisfy { !$0.identifier.isEmpty })
    }

    @Test func readsBuiltInListsInOrder() async throws {
        for source in ThingsSource.builtInLists {
            _ = try await client.todos(in: source) // must not throw for any built-in list
        }
    }

    @Test func fullLifecycle() async throws {
        let title = "\(tag) lifecycle"
        try await client.add(TodoDraft(title: title, notes: "created by test", tags: ["Home"]), to: .today)
        var item = try #require(try await find(title))
        #expect(item.notes == "created by test")
        #expect(item.tags == ["Home"])

        // Edit via URL scheme (needs the auth token).
        let deadline = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        try await client.update(id: item.id, changes: TodoChanges(title: title + " edited", notes: "changed",
                                                                  tags: ["Office"], deadline: .some(deadline)))
        item = try #require(try await find(title + " edited"))
        #expect(item.notes == "changed")
        #expect(item.tags == ["Office"])
        #expect(item.deadline.map { Calendar.current.isDate($0, inSameDayAs: deadline) } == true)

        // Clear the deadline.
        try await client.update(id: item.id, changes: TodoChanges(deadline: .some(nil)))
        #expect(try await find(title + " edited")?.deadline == nil)

        // Complete: leaves Today.
        try await client.complete(id: item.id)
        #expect(try await find(title + " edited") == nil)
        try await client.delete(id: item.id) // tidy up the logbook entry too
    }

    @Test func addToProjectThenDeleteGoesToTrash() async throws {
        let projects = try await client.catalog().projects
        let project = try #require(projects.first)
        let title = "\(tag) in project"
        try await client.add(TodoDraft(title: title), to: project)
        let item = try #require(try await find(title, in: project))
        #expect(item.projectID == project.identifier)
        #expect(try await client.todos(in: project).first?.title == title, "new to-dos go to the top")

        try await client.delete(id: item.id)
        #expect(try await find(title, in: project) == nil)
        let trash = ThingsSource(kind: .list, identifier: "TMTrashListSource", name: "Trash")
        #expect(try await client.todos(in: trash).contains { $0.title == title })
    }

    @Test func cancelLeavesList() async throws {
        let title = "\(tag) cancel"
        try await client.add(TodoDraft(title: title), to: .today)
        let item = try #require(try await find(title))
        try await client.cancel(id: item.id)
        #expect(try await find(title) == nil)
        try await client.delete(id: item.id)
    }

    @Test func updateWithoutTokenFailsFastWithoutSendingAnything() async throws {
        let noToken = LiveThingsClient(opener: ShellOpener(), authToken: { nil })
        await #expect(throws: ThingsError.missingAuthToken) {
            try await noToken.update(id: "whatever", changes: TodoChanges(title: "x"))
        }
    }

    @Test func specialCharactersSurviveRoundTrip() async throws {
        let title = "\(tag) A & B + \"quoted\" = #1 ü 🎉"
        try await client.add(TodoDraft(title: title), to: .today)
        let item = try #require(try await find(title))
        try await client.delete(id: item.id)
    }

    @Test func moveToTopOfToday() async throws {
        let a = "\(tag) order A", b = "\(tag) order B"
        try await client.add(TodoDraft(title: a), to: .today)
        try await client.add(TodoDraft(title: b), to: .today) // B is now above A
        let itemA = try #require(try await find(a))
        #expect(try await client.todos(in: .today).first?.title == b)
        try await client.moveToTopOfToday(id: itemA.id)
        let titles = try await client.todos(in: .today).map(\.title)
        #expect(titles.prefix(2) == [a, b])
        for title in [a, b] { if let item = try await find(title) { try await client.delete(id: item.id) } }
    }

    @Test func changeTokenTracksOrderAndEdits() async throws {
        let a = "\(tag) token A", b = "\(tag) token B"
        try await client.add(TodoDraft(title: a), to: .today)
        try await client.add(TodoDraft(title: b), to: .today)
        let itemA = try #require(try await find(a))
        let t1 = try #require(try await client.changeToken(in: .today))
        #expect(try await client.changeToken(in: .today) == t1, "stable while nothing changes")

        try await client.moveToTop(id: itemA.id, in: .today) // a reorder, as if dragged in Things
        let t2 = try #require(try await client.changeToken(in: .today))
        #expect(t2 != t1)

        try await client.update(id: itemA.id, changes: TodoChanges(title: a + " renamed")) // a rename, at once
        let t3 = try #require(try await client.changeToken(in: .today))
        #expect(t3 != t2)

        try await Task.sleep(for: .seconds(1.1)) // modification dates have one-second resolution
        try await client.update(id: itemA.id, changes: TodoChanges(notes: "edited")) // any other edit
        #expect(try await client.changeToken(in: .today) != t3)
        try await client.delete(id: itemA.id)
        for title in [a, b] { if let item = try await find(title) { try await client.delete(id: item.id) } }
    }

    /// Drag-and-drop through the store, as the UI does, against the real Today and Inbox.
    /// A filter shows only this test's to-dos, so the user's own to-dos are hidden and
    /// must keep their order.
    @MainActor @Test(arguments: [ThingsSource.today, ThingsSource.inbox])
    func storeReorderSyncsToThings(source: ThingsSource) async throws {
        let titles = (1...3).map { "\(tag) \(source.name) \($0)" }
        for t in titles { try await client.add(TodoDraft(title: t), to: source) } // 3 2 1 on top
        let othersBefore = try await client.todos(in: source).map(\.id).filter { id in true }
        let settings = MemorySettings()
        settings.stored.source = source
        settings.stored.filter.searchText = tag
        let store = TodoStore(client: client, persistence: settings)
        store.hasAuthToken = token != nil
        store.orderSyncDelay = .milliseconds(50)
        await store.refresh()
        #expect(store.visibleItems.map(\.title) == titles.reversed())

        func thingsOrder() async throws -> [String] {
            try await client.todos(in: source).map(\.title).filter { $0.hasPrefix(tag) }
        }
        func drag(_ title: String, toGap gap: Int) async throws {
            let item = try #require(store.visibleItems.first { $0.title == title })
            store.moveVisible(item, toGap: gap)
            await store.waitForOrderSync()
            #expect(store.errorMessage == nil, "\(store.errorMessage ?? "")")
        }

        try await drag(titles[0], toGap: 0)                    // 1 3 2
        #expect(try await thingsOrder() == [titles[0], titles[2], titles[1]])
        try await drag(titles[0], toGap: 3)                    // 3 2 1
        #expect(try await thingsOrder() == [titles[2], titles[1], titles[0]])
        try await drag(titles[0], toGap: 1)                    // 3 1 2
        #expect(try await thingsOrder() == [titles[2], titles[0], titles[1]])
        #expect(store.visibleItems.map(\.title) == [titles[2], titles[0], titles[1]], "UI shows Things' order")

        let ids = Set(store.items.filter { $0.title.hasPrefix(tag) }.map(\.id))
        let othersAfter = try await client.todos(in: source).map(\.id).filter { !ids.contains($0) }
        #expect(othersAfter == othersBefore.filter { !ids.contains($0) }, "other to-dos keep their order")
        for item in store.items where item.title.hasPrefix(tag) { try await client.delete(id: item.id) }
    }

    /// Undo through the store against the real Things: complete, trash (restored to a
    /// project and to Today with its project kept) and reorder.
    @MainActor @Test func undoRoundTrips() async throws {
        let project = try #require(try await client.catalog().projects.first)
        let titles = ["\(tag) undo A", "\(tag) undo B"]
        try await client.add(TodoDraft(title: titles[0]), to: .today)
        try await client.add(TodoDraft(title: titles[1]), to: .today) // B above A
        let settings = MemorySettings()
        settings.stored.filter.searchText = tag
        let store = TodoStore(client: client, persistence: settings)
        store.hasAuthToken = token != nil
        store.orderSyncDelay = .milliseconds(50)
        await store.refresh()
        func order() async throws -> [String] { try await client.todos(in: .today).map(\.title).filter { $0.hasPrefix(tag) } }

        // Complete → undo: back in Today, same place.
        await store.complete(try #require(store.visibleItems.first { $0.title == titles[0] }))
        #expect(try await order() == [titles[1]])
        await store.undo(); await store.waitForOrderSync()
        #expect(try await order() == [titles[1], titles[0]])

        // Trash → undo: restored to Today in its old place.
        await store.delete(try #require(store.visibleItems.first { $0.title == titles[1] }))
        #expect(try await order() == [titles[0]])
        await store.undo(); await store.waitForOrderSync()
        #expect(try await order() == [titles[1], titles[0]])
        #expect(store.errorMessage == nil, "\(store.errorMessage ?? "")")

        // Reorder → undo.
        store.moveVisible(try #require(store.visibleItems.first { $0.title == titles[0] }), toGap: 0)
        await store.waitForOrderSync()
        #expect(try await order() == [titles[0], titles[1]])
        await store.undo(); await store.waitForOrderSync()
        #expect(try await order() == [titles[1], titles[0]])

        // Trash from a project → restore keeps it in the project.
        let inProject = "\(tag) undo project"
        try await client.add(TodoDraft(title: inProject), to: project)
        let pItem = try #require(try await client.todos(in: project).first { $0.title == inProject })
        try await client.delete(id: pItem.id)
        let target = try #require(UndoSupport.restoreTarget(for: pItem, from: project))
        #expect(target == .anytime)
        try await client.restore(id: pItem.id, to: target)
        #expect(try await client.todos(in: project).contains { $0.id == pItem.id })

        for item in try await client.todos(in: .today) where item.title.hasPrefix(tag) { try await client.delete(id: item.id) }
        try await client.delete(id: pItem.id)
    }
}
