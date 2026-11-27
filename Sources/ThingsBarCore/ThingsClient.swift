import Foundation

/// Everything the app needs from Things.
public protocol ThingsClient: Sendable {
    func catalog() async throws -> SourceCatalog
    /// Open to-dos in Things' own order.
    func todos(in source: ThingsSource) async throws -> [TodoItem]
    /// A cheap fingerprint of a source's to-dos: their order and modification dates.
    /// It changes whenever anything in the list changes, including reordering in Things.
    /// Returns nil if Things isn't running (never launches it).
    func changeToken(in source: ThingsSource) async throws -> String?
    func add(_ draft: TodoDraft, to source: ThingsSource) async throws
    func update(id: String, changes: TodoChanges) async throws
    func complete(id: String) async throws
    func cancel(id: String) async throws
    /// Moves the to-do to Things' Trash.
    func delete(id: String) async throws
    /// Opens the to-do in Things (brings Things to the front).
    func reveal(id: String) async throws
    /// Moves a to-do to the top of `source`. Only lists where `ReorderPlan.isSupported`
    /// is true can be reordered; others throw `reorderUnsupported`.
    func moveToTop(id: String, in source: ThingsSource) async throws
}

/// Opens `things:///` URLs and launches Things. The app implements this with NSWorkspace.
public protocol URLOpening: Sendable {
    func open(_ url: URL, activate: Bool) async throws
    /// Launches Things in the background if it isn't running.
    func launchThings() async throws
}

/// Reads and changes status/deletes via Apple Events (Things' scripting interface);
/// adds and edits via the documented URL scheme. See README for why.
public final class LiveThingsClient: ThingsClient {
    private let transport: AppleEventSending
    private let opener: URLOpening
    private let authToken: @Sendable () -> String?
    private let pollInterval: Duration
    private let pollTimeout: Duration

    public init(transport: AppleEventSending = ThingsAppleEventTransport(), opener: URLOpening,
                authToken: @escaping @Sendable () -> String?,
                pollInterval: Duration = .milliseconds(150), pollTimeout: Duration = .seconds(5)) {
        self.transport = transport; self.opener = opener; self.authToken = authToken
        self.pollInterval = pollInterval; self.pollTimeout = pollTimeout
    }

    // MARK: - Reading

    /// `get <property> of <specifier>`, launching Things once if it isn't running.
    private func get<T: Sendable>(_ spec: @escaping @Sendable () -> NSAppleEventDescriptor,
                                  decode: @escaping @Sendable (NSAppleEventDescriptor) throws -> T) async throws -> T {
        do {
            return try await transport.send({ ThingsEvent.get(spec()) }, decode: decode)
        } catch ThingsError.thingsNotRunning {
            try await opener.launchThings()
            return try await transport.send({ ThingsEvent.get(spec()) }, decode: decode)
        }
    }

    /// One event per property of `every <class> of <container>` (AppleScript does the same).
    private func columns(of cls: FourCharCode, in container: @escaping @Sendable () -> NSAppleEventDescriptor,
                         properties: [FourCharCode]) async throws -> [[NSAppleEventDescriptor]] {
        var cols: [[NSAppleEventDescriptor]] = []
        for prop in properties {
            let col = try await get({ Specifier.property(prop, of: Specifier.every(cls, in: container())) }) { d in
                UncheckedBox(value: Descriptor.list(d))
            }
            cols.append(col.value)
        }
        guard Set(cols.map(\.count)).count <= 1 else {
            throw ThingsError.unexpectedResponse("Things changed while reading; try again")
        }
        return cols
    }

    public func catalog() async throws -> SourceCatalog {
        let p = try await columns(of: Code.project, in: { Specifier.app }, properties: [Code.id, Code.name, Code.status])
        let a = try await columns(of: Code.area, in: { Specifier.app }, properties: [Code.id, Code.name])
        let t = try await columns(of: Code.tag, in: { Specifier.app }, properties: [Code.name])
        let projects = p.isEmpty ? [] : p[0].indices.compactMap { i -> ThingsSource? in
            guard p[2][i].enumCodeValue == Code.open, let id = Descriptor.string(p[0][i]) else { return nil }
            return ThingsSource(kind: .project, identifier: id, name: Descriptor.string(p[1][i]) ?? "Untitled")
        }
        let areas = a.isEmpty ? [] : a[0].indices.compactMap { i -> ThingsSource? in
            guard let id = Descriptor.string(a[0][i]) else { return nil }
            return ThingsSource(kind: .area, identifier: id, name: Descriptor.string(a[1][i]) ?? "Untitled")
        }
        let tags = (t.first ?? []).compactMap(Descriptor.string).map { ThingsSource(kind: .tag, identifier: $0, name: $0) }
        return SourceCatalog(projects: projects, areas: areas, tags: tags)
    }

    static let todoProperties = [Code.id, Code.name, Code.notes, Code.tagNames, Code.dueDate,
                                 Code.activationDate, Code.project, Code.area, Code.status]

    public func todos(in source: ThingsSource) async throws -> [TodoItem] {
        do {
            let cols = try await columns(of: Code.todo, in: { Specifier.container(for: source) },
                                         properties: Self.todoProperties)
            return try Self.decodeTodos(cols)
        } catch let ThingsError.script(number, _) where number == -1728 || number == -1719 {
            throw ThingsError.sourceNotFound(source.name) // errAENoSuchObject / errAEIllegalIndex
        }
    }

    public func changeToken(in source: ThingsSource) async throws -> String? {
        @Sendable func column(_ prop: FourCharCode) async throws -> [String] {
            try await transport.send({
                ThingsEvent.get(Specifier.property(prop, of: Specifier.every(Code.todo, in: Specifier.container(for: source))))
            }, decode: { d in
                Descriptor.list(d).map { Descriptor.date($0).map { String($0.timeIntervalSinceReferenceDate) } ?? Descriptor.string($0) ?? "∅" }
            })
        }
        do {
            // Modification dates have one-second resolution, so titles are included too.
            let ids = try await column(Code.id)
            let modified = try await column(Code.modificationDate)
            let names = try await column(Code.name)
            guard ids.count == modified.count, ids.count == names.count else { return UUID().uuidString } // changed mid-read
            return ids.indices.map { "\(ids[$0])@\(modified[$0])#\(names[$0])" }.joined(separator: "\u{1F}")
        } catch ThingsError.thingsNotRunning {
            return nil
        }
    }

    /// Builds to-dos from property columns, keeping only open ones, in Things' order.
    static func decodeTodos(_ c: [[NSAppleEventDescriptor]]) throws -> [TodoItem] {
        guard c.count == todoProperties.count else {
            throw ThingsError.unexpectedResponse("expected \(todoProperties.count) columns, got \(c.count)")
        }
        guard Set(c.map(\.count)).count <= 1 else { throw ThingsError.unexpectedResponse("ragged columns") }
        return c[0].indices.compactMap { i in
            guard let id = Descriptor.string(c[0][i]), c[8][i].enumCodeValue == Code.open else { return nil }
            return TodoItem(id: id,
                            title: Descriptor.string(c[1][i]) ?? "",
                            notes: Descriptor.string(c[2][i]) ?? "",
                            tags: Descriptor.tags(c[3][i]),
                            deadline: Descriptor.date(c[4][i]),
                            startDate: Descriptor.date(c[5][i]),
                            projectID: Descriptor.objectID(c[6][i]),
                            areaID: Descriptor.objectID(c[7][i]))
        }
    }

    // MARK: - Writing

    public func add(_ draft: TodoDraft, to source: ThingsSource) async throws {
        @Sendable func matches() async throws -> Int { try await todos(in: source).filter { $0.title == draft.title }.count }
        let before = try await matches()
        try await opener.open(ThingsURL.add(draft, to: source), activate: false)
        try await waitUntil { try await matches() > before }
    }

    public func update(id: String, changes: TodoChanges) async throws {
        guard !changes.isEmpty else { return }
        guard let token = authToken(), !token.isEmpty else { throw ThingsError.missingAuthToken }
        let before = try await snapshot(id: id)
        try await opener.open(ThingsURL.update(id: id, changes: changes, authToken: token), activate: false)
        try await waitUntil { try await self.snapshot(id: id) != before }
    }

    public func complete(id: String) async throws { try await setStatus(id: id, Code.completed) }
    public func cancel(id: String) async throws { try await setStatus(id: id, Code.canceled) }

    private func setStatus(id: String, _ status: FourCharCode) async throws {
        try await transport.send({
            ThingsEvent.set(Specifier.property(Code.status, of: Specifier.byID(Code.todo, id)),
                            to: NSAppleEventDescriptor(enumCode: status))
        }, decode: { _ in () })
    }

    public func delete(id: String) async throws {
        try await transport.send({ ThingsEvent.delete(Specifier.byID(Code.todo, id)) }, decode: { _ in () })
    }

    public func reveal(id: String) async throws {
        try await opener.open(ThingsURL.show(id: id), activate: true)
    }

    public func moveToTop(id: String, in source: ThingsSource) async throws {
        switch source {
        case .today: try await moveToTopOfToday(id: id)
        case .inbox: try await moveToTopOfInbox(id: id)
        default: throw ThingsError.reorderUnsupported(source.name)
        }
    }

    /// Moving a to-do into the Inbox puts it first, but moving it to the list it's
    /// already in does nothing, so hop through Someday (Inbox items have no other
    /// state to lose). Synchronous Apple Events; no auth token needed.
    func moveToTopOfInbox(id: String) async throws {
        let someday = ThingsSource.someday.identifier, inbox = ThingsSource.inbox.identifier
        for list in [someday, inbox] {
            try await transport.send({ ThingsEvent.move(Specifier.byID(Code.todo, id), to: Specifier.byID(Code.list, list)) },
                                     decode: { _ in () })
        }
        try await waitUntil { try await self.todos(in: .inbox).first?.id == id }
    }

    /// Rescheduling This Evening → Today puts a to-do first in Today.
    public func moveToTopOfToday(id: String) async throws {
        guard let token = authToken(), !token.isEmpty else { throw ThingsError.missingAuthToken }
        // Not verified step by step: both steps can land within the same second, so the
        // modification date may not change between them. Things handles URLs in order;
        // the final position is what we check.
        try await opener.open(ThingsURL.update(id: id, changes: TodoChanges(when: .evening), authToken: token), activate: false)
        try await opener.open(ThingsURL.update(id: id, changes: TodoChanges(when: .today), authToken: token), activate: false)
        try await waitUntil { try await self.todos(in: .today).first?.id == id }
    }

    // MARK: - Verifying URL-scheme writes

    /// Fields a URL `update` can change, from one `properties of to do id …` event.
    private func snapshot(id: String) async throws -> [String] {
        try await get({ Specifier.property(Code.allProperties, of: Specifier.byID(Code.todo, id)) }) { record in
            [Code.name, Code.notes, Code.tagNames, Code.dueDate, Code.activationDate, Code.modificationDate].map { key in
                guard let d = record.forKeyword(key) else { return "∅" }
                if let date = Descriptor.date(d) { return String(date.timeIntervalSinceReferenceDate) }
                return Descriptor.string(d) ?? "∅"
            }
        }
    }

    private func waitUntil(_ condition: @Sendable () async throws -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: pollTimeout)
        while clock.now < deadline {
            try await Task.sleep(for: pollInterval)
            if try await condition() { return }
        }
        throw ThingsError.changeNotApplied
    }
}

/// Moves non-Sendable descriptors across the transport boundary. Safe because
/// descriptors are immutable once decoded and only read afterwards.
struct UncheckedBox<T>: @unchecked Sendable { let value: T }
