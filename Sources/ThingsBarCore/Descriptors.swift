import Foundation

/// Helpers for reading Things' bulk AppleScript results, which come back as a
/// list of columns: `{ {id1, id2…}, {name1, name2…}, … }`.
enum Descriptor {
    static let missingValueCode: OSType = Code.missingValue

    static func list(_ d: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        guard d.descriptorType == typeAEList, d.numberOfItems > 0 else { return [] }
        return (1...d.numberOfItems).compactMap { d.atIndex($0) }
    }

    /// Returns `count` columns of equal length, or throws if the shape is wrong.
    static func columns(_ d: NSAppleEventDescriptor, count: Int) throws -> [[NSAppleEventDescriptor]] {
        let cols = list(d).map(list)
        guard cols.count == count else {
            throw ThingsError.unexpectedResponse("expected \(count) columns, got \(cols.count)")
        }
        let rows = cols.first?.count ?? 0
        guard cols.allSatisfy({ $0.count == rows }) else {
            throw ThingsError.unexpectedResponse("ragged columns")
        }
        return cols
    }

    static func isMissing(_ d: NSAppleEventDescriptor) -> Bool {
        d.descriptorType == typeType && d.typeCodeValue == missingValueCode
            || d.descriptorType == typeNull
    }

    static func string(_ d: NSAppleEventDescriptor) -> String? {
        isMissing(d) ? nil : d.stringValue
    }

    static func date(_ d: NSAppleEventDescriptor) -> Date? {
        isMissing(d) ? nil : d.dateValue
    }

    /// The ID inside an object specifier like `project id "abc" of application "Things3"`.
    static func objectID(_ d: NSAppleEventDescriptor) -> String? {
        guard d.descriptorType == typeObjectSpecifier else { return nil }
        return d.forKeyword(AEKeyword(keyAEKeyData))?.stringValue
    }

    /// "Office, Home" → ["Office", "Home"]
    static func tags(_ d: NSAppleEventDescriptor) -> [String] {
        (string(d) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
