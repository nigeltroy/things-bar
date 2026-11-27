import Foundation

/// Four-char codes from Things 3's scripting definition (`sdef /Applications/Things3.app`).
enum Code {
    static func fourCC(_ s: String) -> FourCharCode {
        s.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
    // Classes
    static let todo = fourCC("tstk"), project = fourCC("tspt"), area = fourCC("tsaa")
    static let list = fourCC("tsls"), tag = fourCC("tstg")
    // Properties
    static let id = fourCC("ID  "), name = fourCC("pnam"), notes = fourCC("note"), tagNames = fourCC("tnam")
    static let dueDate = fourCC("dued"), activationDate = fourCC("actd"), modificationDate = fourCC("modd")
    static let status = fourCC("tdst"), allProperties = fourCC("pALL")
    // Status enumerators
    static let open = fourCC("tdio"), completed = fourCC("tdcm"), canceled = fourCC("tdcl")
    // AppleScript `missing value`
    static let missingValue = fourCC("msng")
}

/// Builds Apple Event object specifiers: the "noun phrases" AppleScript compiles to,
/// e.g. `name of every to do of list id "TMTodayListSource"`.
enum Specifier {
    private static func make(want: FourCharCode, from container: NSAppleEventDescriptor,
                             form: FourCharCode, data: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let spec = NSAppleEventDescriptor.record().coerce(toDescriptorType: typeObjectSpecifier)!
        spec.setDescriptor(NSAppleEventDescriptor(typeCode: want), forKeyword: AEKeyword(keyAEDesiredClass))
        spec.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        spec.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        spec.setDescriptor(data, forKeyword: AEKeyword(keyAEKeyData))
        return spec
    }

    /// The application itself (the outermost container).
    static var app: NSAppleEventDescriptor { .null() }

    static func byID(_ cls: FourCharCode, _ id: String, in container: NSAppleEventDescriptor = app) -> NSAppleEventDescriptor {
        make(want: cls, from: container, form: FourCharCode(formUniqueID), data: NSAppleEventDescriptor(string: id))
    }

    static func byName(_ cls: FourCharCode, _ name: String, in container: NSAppleEventDescriptor = app) -> NSAppleEventDescriptor {
        make(want: cls, from: container, form: FourCharCode(formName), data: NSAppleEventDescriptor(string: name))
    }

    static func every(_ cls: FourCharCode, in container: NSAppleEventDescriptor = app) -> NSAppleEventDescriptor {
        let all = NSAppleEventDescriptor(descriptorType: typeAbsoluteOrdinal, bytes: [FourCharCode(kAEAll)], length: 4)! // native byte order, like every other descriptor
        return make(want: cls, from: container, form: FourCharCode(formAbsolutePosition), data: all)
    }

    static func property(_ code: FourCharCode, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        make(want: FourCharCode(cProperty), from: container, form: FourCharCode(formPropertyID),
             data: NSAppleEventDescriptor(typeCode: code))
    }

    static func container(for source: ThingsSource) -> NSAppleEventDescriptor {
        switch source.kind {
        case .list: byID(Code.list, source.identifier)
        case .project: byID(Code.project, source.identifier)
        case .area: byID(Code.area, source.identifier)
        case .tag: byName(Code.tag, source.identifier)
        }
    }
}

/// Sends Apple Events to Things. Unlike NSAppleScript, raw Apple Events are safe
/// to send off the main thread while the main run loop is busy (verified: NSAppleScript
/// on a background thread deadlocks in any process with a main run loop).
public protocol AppleEventSending: Sendable {
    /// Builds and sends an event on the transport's queue; returns the decoded reply.
    func send<T: Sendable>(_ build: @escaping @Sendable () -> NSAppleEventDescriptor,
                           decode: @escaping @Sendable (NSAppleEventDescriptor) throws -> T) async throws -> T
}

public final class ThingsAppleEventTransport: AppleEventSending, @unchecked Sendable {
    public static let bundleID = "com.culturedcode.ThingsMac"
    private let queue = DispatchQueue(label: "local.thingsbar.appleevents", qos: .userInitiated)
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 15) { self.timeout = timeout }

    public func send<T: Sendable>(_ build: @escaping @Sendable () -> NSAppleEventDescriptor,
                                  decode: @escaping @Sendable (NSAppleEventDescriptor) throws -> T) async throws -> T {
        let timeout = self.timeout
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    let event = build()
                    let reply: NSAppleEventDescriptor
                    do {
                        reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: timeout)
                    } catch let error as NSError {
                        throw Self.mapError(number: error.code, message: error.localizedDescription)
                    }
                    if let errn = reply.paramDescriptor(forKeyword: keyErrorNumber), errn.int32Value != 0 {
                        let msg = reply.paramDescriptor(forKeyword: keyErrorString)?.stringValue ?? "Apple Event error"
                        throw Self.mapError(number: Int(errn.int32Value), message: msg)
                    }
                    return try decode(reply.paramDescriptor(forKeyword: keyDirectObject) ?? .null())
                })
            }
        }
    }

    static func mapError(number: Int, message: String) -> ThingsError {
        switch number {
        case -1743, -1744: .automationDenied
        case -1712: .timedOut
        case -600, -609: .thingsNotRunning
        case -10814: .thingsNotInstalled
        default: .script(number: number, message: message)
        }
    }
}

/// Event constructors for the handful of commands ThingsBar uses.
enum ThingsEvent {
    private static var target: NSAppleEventDescriptor {
        NSAppleEventDescriptor(bundleIdentifier: ThingsAppleEventTransport.bundleID)
    }

    private static func event(_ cls: String, _ id: String, direct: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let e = NSAppleEventDescriptor(eventClass: Code.fourCC(cls), eventID: Code.fourCC(id), targetDescriptor: target,
                                       returnID: AEReturnID(kAutoGenerateReturnID),
                                       transactionID: AETransactionID(kAnyTransactionID))
        e.setParam(direct, forKeyword: keyDirectObject)
        return e
    }

    static func get(_ spec: NSAppleEventDescriptor) -> NSAppleEventDescriptor { event("core", "getd", direct: spec) }

    static func set(_ spec: NSAppleEventDescriptor, to value: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let e = event("core", "setd", direct: spec)
        e.setParam(value, forKeyword: AEKeyword(keyAEData))
        return e
    }

    /// Things' `delete` moves to-dos to the Trash.
    static func delete(_ spec: NSAppleEventDescriptor) -> NSAppleEventDescriptor { event("core", "delo", direct: spec) }
}
