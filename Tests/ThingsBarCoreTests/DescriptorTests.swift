import Foundation
import Testing
@testable import ThingsBarCore

/// Builds descriptors shaped exactly like Things' replies (verified with Things 3.25).
struct DescriptorTests {
    func list(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let l = NSAppleEventDescriptor.list()
        for (i, item) in items.enumerated() { l.insert(item, at: i + 1) }
        return l
    }
    func str(_ s: String) -> NSAppleEventDescriptor { NSAppleEventDescriptor(string: s) }
    var missing: NSAppleEventDescriptor { NSAppleEventDescriptor(typeCode: Descriptor.missingValueCode) }
    func projectRef(_ id: String) -> NSAppleEventDescriptor {
        let obj = NSAppleEventDescriptor.record().coerce(toDescriptorType: typeObjectSpecifier)!
        obj.setDescriptor(NSAppleEventDescriptor(typeCode: 0x7473_7074), forKeyword: AEKeyword(keyAEDesiredClass))
        obj.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formUniqueID)), forKeyword: AEKeyword(keyAEKeyForm))
        obj.setDescriptor(str(id), forKeyword: AEKeyword(keyAEKeyData))
        return obj
    }

    var open: NSAppleEventDescriptor { NSAppleEventDescriptor(enumCode: Code.open) }
    var done: NSAppleEventDescriptor { NSAppleEventDescriptor(enumCode: Code.completed) }

    @Test func decodesTodoColumnsAndSkipsClosedItems() throws {
        let deadline = Date(timeIntervalSince1970: 1_796_000_000)
        let cols: [[NSAppleEventDescriptor]] = [
            [str("id1"), str("id2"), str("id3")],
            [str("First"), str("Second"), str("Done one")],
            [str("notes"), str(""), str("")],
            [str("Office, Home"), str(""), str("")],
            [NSAppleEventDescriptor(date: deadline), missing, missing],
            [missing, missing, missing],
            [projectRef("P9"), missing, missing],
            [missing, missing, missing],
            [open, open, done],
        ]
        let todos = try LiveThingsClient.decodeTodos(cols)
        #expect(todos.map(\.id) == ["id1", "id2"])
        #expect(todos[0].tags == ["Office", "Home"])
        #expect(todos[0].deadline == deadline)
        #expect(todos[0].projectID == "P9")
        #expect(todos[1].deadline == nil && todos[1].projectID == nil && todos[1].tags.isEmpty)
    }

    @Test func emptyColumnsDecodeToNothing() throws {
        #expect(try LiveThingsClient.decodeTodos(Array(repeating: [], count: 9)).isEmpty)
    }

    @Test func wrongShapeThrows() {
        #expect(throws: ThingsError.self) { try LiveThingsClient.decodeTodos([[str("a")]]) }
        #expect(throws: ThingsError.self) {
            try LiveThingsClient.decodeTodos([[str("a")]] + Array(repeating: [], count: 8))
        }
    }

    @Test func specifierShape() {
        let spec = Specifier.property(Code.name, of: Specifier.every(Code.todo, in: Specifier.container(for: .today)))
        #expect(spec.descriptorType == typeObjectSpecifier)
        #expect(spec.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue == Code.name)
        let every = spec.forKeyword(AEKeyword(keyAEContainer))!
        #expect(every.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue == Code.todo)
        let list = every.forKeyword(AEKeyword(keyAEContainer))!
        #expect(Descriptor.objectID(list) == "TMTodayListSource")
        #expect(Code.fourCC("tstk") == 0x7473_746B)
    }

    @Test func errorMapping() {
        #expect(ThingsAppleEventTransport.mapError(number: -1743, message: "") == .automationDenied)
        #expect(ThingsAppleEventTransport.mapError(number: -1712, message: "") == .timedOut)
        #expect(ThingsAppleEventTransport.mapError(number: -600, message: "") == .thingsNotRunning)
        #expect(ThingsAppleEventTransport.mapError(number: -1728, message: "x") == .script(number: -1728, message: "x"))
    }
}
