import Foundation
import Testing
@testable import ThingsBarCore

struct ThingsURLTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    func params(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value?.removingPercentEncoding ?? "") })
    }

    @Test func encodesReservedCharacters() {
        let url = ThingsURL.add(TodoDraft(title: "A & B + C = #1\nline2"), to: .inbox)
        #expect(url.absoluteString == "things:///add?title=A%20%26%20B%20%2B%20C%20%3D%20%231%0Aline2")
        #expect(params(url)["title"] == "A & B + C = #1\nline2")
    }

    @Test func addToBuiltInListsUsesWhen() {
        #expect(params(ThingsURL.add(TodoDraft(title: "x"), to: .today))["when"] == "today")
        #expect(params(ThingsURL.add(TodoDraft(title: "x"), to: .someday))["when"] == "someday")
        #expect(params(ThingsURL.add(TodoDraft(title: "x"), to: .anytime))["when"] == "anytime")
        #expect(params(ThingsURL.add(TodoDraft(title: "x"), to: .inbox))["when"] == nil)
    }

    @Test func addToProjectAreaAndTag() {
        let proj = ThingsSource(kind: .project, identifier: "P1", name: "Proj")
        #expect(params(ThingsURL.add(TodoDraft(title: "x"), to: proj))["list-id"] == "P1")
        let tag = ThingsSource(kind: .tag, identifier: "Home", name: "Home")
        #expect(params(ThingsURL.add(TodoDraft(title: "x", tags: ["Office"]), to: tag))["tags"] == "Office,Home")
        #expect(params(ThingsURL.add(TodoDraft(title: "x", tags: ["Home"]), to: tag))["tags"] == "Home")
    }

    @Test func addWithDeadlineAndNotes() {
        let d = cal.date(from: DateComponents(year: 2026, month: 12, day: 5))!
        let p = params(ThingsURL.add(TodoDraft(title: "x", notes: "n", deadline: d), to: .inbox, calendar: cal))
        #expect(p["deadline"] == "2026-12-05")
        #expect(p["notes"] == "n")
    }

    @Test func updateCarriesTokenAndOnlyChangedFields() {
        let url = ThingsURL.update(id: "T1", changes: TodoChanges(title: "New"), authToken: "tok")
        #expect(params(url) == ["auth-token": "tok", "id": "T1", "title": "New"])
    }

    @Test func updateCanClearDeadlineAndSchedule() {
        let p = params(ThingsURL.update(id: "T1", changes: TodoChanges(deadline: .some(nil), when: .evening), authToken: "t"))
        #expect(p["deadline"] == "")
        #expect(p["when"] == "evening")
    }
}

struct TokenCheckTests {
    @Test func tokenCheckURLTargetsANonexistentToDo() {
        let url = ThingsURL.tokenCheck(authToken: "T&1", requestID: "R1").absoluteString
        #expect(url.hasPrefix("things:///update?auth-token=T%261&id=thingsbar-token-check-R1"))
        #expect(url.contains("x-success=thingsbar%3A%2F%2Ftoken-check%3Frequest%3DR1%26result%3Dsuccess"))
        #expect(url.contains("x-error="))
    }

    @Test func interpretsThingsReplies() {
        #expect(TokenCheck.interpret(result: "error", errorCode: "-12", errorMessage: "Cannot update to-do…") == .valid)
        #expect(TokenCheck.interpret(result: "success", errorCode: nil, errorMessage: nil) == .valid)
        #expect(TokenCheck.interpret(result: nil, errorCode: nil, errorMessage: nil) == .invalid(TokenCheck.rejected))
        #expect(TokenCheck.interpret(result: "error", errorCode: "-5", errorMessage: "Nope") == .invalid("Things: Nope"))
    }
}
