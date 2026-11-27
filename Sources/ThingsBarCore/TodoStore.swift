import Foundation
import Observation

/// App state: the chosen source's to-dos, the catalog of sources, and errors.
@MainActor @Observable
public final class TodoStore {
    public private(set) var catalog = SourceCatalog()
    /// Open to-dos of the current source, unfiltered, in Things' order.
    public private(set) var items: [TodoItem] = []
    public private(set) var errorMessage: String?
    public private(set) var isLoading = false
    public private(set) var lastRefresh: Date?
    /// Whether a Things auth token is saved (edits need one). Set by the app.
    public var hasAuthToken = false

    public var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            persistence.save(settings)
            if settings.source != oldValue.source {
                items = []
                Task { await refresh() }
            }
        }
    }

    public var visibleItems: [TodoItem] { settings.filter.apply(to: items) }
    public var topItem: TodoItem? { visibleItems.first }
    public var menuBarTitle: String {
        MenuBarTitle.make(items: visibleItems, settings: settings)
    }

    @ObservationIgnored public let client: ThingsClient
    @ObservationIgnored private let persistence: SettingsPersisting
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Fingerprint of the source at the last refresh (see `checkForChanges`).
    @ObservationIgnored private var lastChangeToken: String?
    /// A successful refresh only clears errors that a refresh caused, not action errors.
    @ObservationIgnored private var errorCameFromRefresh = false

    public init(client: ThingsClient, persistence: SettingsPersisting) {
        self.client = client
        self.persistence = persistence
        self.settings = persistence.load()
    }

    /// Re-reads the catalog and the current source. Concurrent calls share one read.
    public func refresh() async {
        if let running = refreshTask { return await running.value }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        isLoading = true
        defer { isLoading = false }
        let source = settings.source
        do {
            // Read the fingerprint first: a change during the read then triggers one more refresh.
            let token = try? await client.changeToken(in: source)
            async let cat = client.catalog()
            async let todos = client.todos(in: source)
            let (newCatalog, newItems) = try await (cat, todos)
            catalog = newCatalog
            guard source == settings.source else { return } // source changed mid-read
            items = newItems
            lastChangeToken = token
            if errorCameFromRefresh { errorMessage = nil }
            lastRefresh = Date()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorCameFromRefresh = true
        }
    }

    /// Cheap poll (two small Apple Events): refreshes only if the source changed in
    /// Things since the last refresh. Skipped while ThingsBar itself is changing things.
    public func checkForChanges() async {
        guard refreshTask == nil, pendingIDs.isEmpty, !isAdding, !isBusyReordering else { return }
        let source = settings.source
        guard let token = try? await client.changeToken(in: source), source == settings.source else { return }
        if token != lastChangeToken { await refresh() }
    }

    // MARK: - Reorder (stub; implemented with drag and drop)
    public private(set) var isSyncingOrder = false
    var isBusyReordering: Bool { isSyncingOrder }
    public var canReorder: Bool { false }
    public var reorderUnavailableReason: String? { nil }
    public func moveVisible(_ item: TodoItem, to index: Int) {}

    public func dismissError() { errorMessage = nil; errorCameFromRefresh = false }

    // MARK: - Actions

    /// IDs with a write in flight (rows show a spinner / disable controls).
    public private(set) var pendingIDs: Set<String> = []
    public private(set) var isAdding = false

    /// Adds to the current source. Returns false if Things rejected it.
    @discardableResult
    public func add(_ draft: TodoDraft) async -> Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        var draft = draft
        draft.title = title
        isAdding = true
        defer { isAdding = false }
        let ok = await perform { try await self.client.add(draft, to: self.settings.source) }
        await refresh()
        return ok
    }

    public func complete(_ item: TodoItem) async { await removeOptimistically(item) { try await self.client.complete(id: item.id) } }
    public func cancel(_ item: TodoItem) async { await removeOptimistically(item) { try await self.client.cancel(id: item.id) } }
    public func delete(_ item: TodoItem) async { await removeOptimistically(item) { try await self.client.delete(id: item.id) } }

    /// Applies only the fields that actually differ from `item`.
    @discardableResult
    public func update(_ item: TodoItem, changes: TodoChanges) async -> Bool {
        let diff = changes.minimized(against: item)
        guard !diff.isEmpty else { return true }
        pendingIDs.insert(item.id)
        defer { pendingIDs.remove(item.id) }
        let ok = await perform { try await self.client.update(id: item.id, changes: diff) }
        await refresh()
        return ok
    }

    /// Only Today supports reordering (see ThingsClient.moveToTopOfToday).
    public var canMoveToTop: Bool { settings.source == .today && hasAuthToken }

    public func moveToTop(_ item: TodoItem) async {
        guard canMoveToTop, let index = items.firstIndex(where: { $0.id == item.id }), index > 0 else { return }
        let previous = items
        pendingIDs.insert(item.id)
        items.insert(items.remove(at: index), at: 0) // optimistic
        let ok = await perform { try await self.client.moveToTopOfToday(id: item.id) }
        pendingIDs.remove(item.id)
        if !ok { items = previous }
        await refresh()
    }

    public func reveal(_ item: TodoItem) async {
        await perform { try await self.client.reveal(id: item.id) }
    }

    /// Hides the row immediately; puts it back if Things refuses.
    private func removeOptimistically(_ item: TodoItem, _ action: @escaping () async throws -> Void) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        pendingIDs.insert(item.id)
        items.remove(at: index)
        let ok = await perform(action)
        pendingIDs.remove(item.id)
        if !ok { items.insert(item, at: min(index, items.count)) }
        await refresh()
    }

    @discardableResult
    private func perform(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorCameFromRefresh = false
            return false
        }
    }
}

extension TodoChanges {
    /// Drops fields equal to the item's current values, so URL updates only touch real edits.
    public func minimized(against item: TodoItem, calendar: Calendar = .current) -> TodoChanges {
        var c = self
        if c.title == item.title { c.title = nil }
        if c.notes == item.notes { c.notes = nil }
        if let tags = c.tags, tags == item.tags { c.tags = nil }
        if let deadline = c.deadline {
            let same = switch (deadline, item.deadline) {
            case (nil, nil): true
            case let (a?, b?): calendar.isDate(a, inSameDayAs: b)
            default: false
            }
            if same { c.deadline = nil }
        }
        return c
    }
}
