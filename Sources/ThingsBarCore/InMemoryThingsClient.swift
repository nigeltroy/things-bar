import Foundation

/// A fake Things for unit tests and UI previews/self-tests.
public actor InMemoryThingsClient: ThingsClient {
    public private(set) var catalogValue: SourceCatalog
    public private(set) var items: [String: [TodoItem]] // source.id → ordered to-dos
    public private(set) var log: [String] = []
    public var failNextCall: ThingsError?
    private var nextID = 1

    public init(catalog: SourceCatalog = SourceCatalog(), items: [ThingsSource: [TodoItem]] = [:]) {
        self.catalogValue = catalog
        self.items = Dictionary(uniqueKeysWithValues: items.map { ($0.key.id, $0.value) })
    }

    public func setFailNextCall(_ error: ThingsError?) { failNextCall = error }

    private func check() throws {
        if let e = failNextCall { failNextCall = nil; throw e }
    }

    public func catalog() async throws -> SourceCatalog { try check(); return catalogValue }

    public func todos(in source: ThingsSource) async throws -> [TodoItem] {
        try check(); return items[source.id] ?? []
    }

    public func add(_ draft: TodoDraft, to source: ThingsSource) async throws {
        try check()
        let item = TodoItem(id: "mem-\(nextID)", title: draft.title, notes: draft.notes, tags: draft.tags,
                            deadline: draft.deadline,
                            projectID: source.kind == .project ? source.identifier : nil)
        nextID += 1
        items[source.id, default: []].insert(item, at: 0)
        log.append("add \(draft.title)")
    }

    public func update(id: String, changes: TodoChanges) async throws {
        try check()
        mutate(id) { item in
            if let t = changes.title { item.title = t }
            if let n = changes.notes { item.notes = n }
            if let tags = changes.tags { item.tags = tags }
            if let d = changes.deadline { item.deadline = d }
        }
        log.append("update \(id)")
    }

    public func complete(id: String) async throws { try check(); remove(id); log.append("complete \(id)") }
    public func cancel(id: String) async throws { try check(); remove(id); log.append("cancel \(id)") }
    public func delete(id: String) async throws { try check(); remove(id); log.append("delete \(id)") }
    public func reveal(id: String) async throws { try check(); log.append("reveal \(id)") }

    private func mutate(_ id: String, _ body: (inout TodoItem) -> Void) {
        for key in items.keys {
            if let i = items[key]!.firstIndex(where: { $0.id == id }) { body(&items[key]![i]) }
        }
    }

    private func remove(_ id: String) {
        for key in items.keys { items[key]!.removeAll { $0.id == id } }
    }
}
