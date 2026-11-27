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

        try await client.moveToTopOfToday(id: itemA.id) // a reorder, as if dragged in Things
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
}
