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
        if items.isEmpty && lastRefresh == nil { return "ThingsBar" } // not read yet: "All clear" would be a guess
        return MenuBarTitle.make(items: visibleItems, settings: settings, measure: measureMenuBarText)
    }
    /// Measures text in the menu bar font (set by the app) so titles fit by width.
    @ObservationIgnored public var measureMenuBarText: ((String) -> Double)?

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
            guard !isBusyReordering else { return }          // keep the order the user just dropped
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


    // MARK: - Reorder

    /// True while ThingsBar is writing a new order to Things.
    public private(set) var isSyncingOrder = false
    /// Briefly true after an order was saved and verified (for a quiet confirmation).
    public private(set) var orderJustSaved = false
    /// A dropped order is waiting to be written to Things.
    public private(set) var hasPendingOrder = false
    @ObservationIgnored private var orderSyncTask: Task<Void, Never>?
    /// Pause after the last move before syncing, so a burst of moves syncs once.
    @ObservationIgnored public var orderSyncDelay: Duration = .milliseconds(600)
    var isBusyReordering: Bool { isSyncingOrder || hasPendingOrder }

    public var canReorder: Bool { reorderUnavailableReason == nil }

    /// Why the current list can't be reordered from ThingsBar, or nil if it can.
    public var reorderUnavailableReason: String? {
        guard ReorderPlan.isSupported(in: settings.source) else { return "Reordering works in Today and Inbox" }
        if settings.source == .today && !hasAuthToken { return "Add your auth token in Settings to reorder" }
        return nil
    }

    /// Drops `item` into `gap` (0…count) of the visible list. The list updates at once;
    /// Things is updated after a short pause (see `orderSyncDelay`).
    public func moveVisible(_ item: TodoItem, toGap gap: Int) {
        guard canReorder,
              let order = ReorderPlan.moveVisible(id: item.id, toGap: gap, visible: visibleItems.map(\.id), all: items.map(\.id))
        else { return }
        let previous = items.map(\.id)
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        items = order.compactMap { byID[$0] }
        hasPendingOrder = true
        orderJustSaved = false
        // A burst of moves undoes as one: keep the order from before the first move.
        if case let .reorder(earlier, source)? = undoAction?.kind, source == settings.source, isBusyReordering, earlier != previous {
            offerUndo(UndoAction(label: "Reordered", kind: .reorder(previous: earlier, source: source)))
        } else {
            offerUndo(UndoAction(label: "Reordered", kind: .reorder(previous: previous, source: settings.source)))
        }
        scheduleOrderSync()
    }

    /// Moves `item` to `index` of the visible list (menu commands and shortcuts).
    public func moveVisible(_ item: TodoItem, to index: Int) {
        guard let from = visibleItems.firstIndex(of: item) else { return }
        let target = max(0, min(index, visibleItems.count - 1))
        moveVisible(item, toGap: target > from ? target + 1 : target)
    }

    /// Waits until queued order changes have been written (used by tests).
    public func waitForOrderSync() async {
        while let task = orderSyncTask { await task.value; if orderSyncTask == task { break } }
    }

    private func scheduleOrderSync() {
        guard !isSyncingOrder else { return } // the running sync picks the new order up
        orderSyncTask?.cancel()
        let delay = orderSyncDelay
        orderSyncTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncOrder()
        }
    }

    private func syncOrder() async {
        if let running = refreshTask { await running.value }
        let source = settings.source
        isSyncingOrder = true
        var desired: [String] = []
        var failure: String?
        while hasPendingOrder, failure == nil, source == settings.source {
            hasPendingOrder = false
            desired = items.map(\.id)
            do {
                let current = try await client.todos(in: source).map(\.id) // fresh: Things may have changed
                for id in ReorderPlan.moveToTopSequence(from: current, to: desired) {
                    try await client.moveToTop(id: id, in: source)
                }
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        isSyncingOrder = false
        hasPendingOrder = false
        if let running = refreshTask { await running.value }
        await refresh() // shows Things' real order: confirms success, or rolls back a failure
        guard source == settings.source else { return }
        if failure == nil {
            let ids = items.map(\.id), common = Set(ids).intersection(desired)
            if ids.filter(common.contains) != desired.filter(common.contains) { failure = "Things didn't keep the new order." }
        }
        if let failure {
            errorMessage = "Couldn't save the new order. \(failure)"
            errorCameFromRefresh = false
        } else {
            orderJustSaved = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.orderJustSaved = false
            }
        }
    }

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

    public func complete(_ item: TodoItem) async {
        let order = items.map(\.id)
        await removeOptimistically(item, { try await self.client.complete(id: item.id) }) {
            self.offerUndo(UndoAction(label: "Completed \u{201C}\(item.title)\u{201D}", kind: .reopen(item, order: order)))
        }
    }

    public func cancel(_ item: TodoItem) async {
        let order = items.map(\.id)
        await removeOptimistically(item, { try await self.client.cancel(id: item.id) }) {
            self.offerUndo(UndoAction(label: "Canceled \u{201C}\(item.title)\u{201D}", kind: .reopen(item, order: order)))
        }
    }

    public func delete(_ item: TodoItem) async {
        let order = items.map(\.id), source = settings.source
        await removeOptimistically(item, { try await self.client.delete(id: item.id) }) {
            guard let target = UndoSupport.restoreTarget(for: item, from: source) else { return }
            self.offerUndo(UndoAction(label: "Moved \u{201C}\(item.title)\u{201D} to Trash",
                                      kind: .restore(item, source: source, target: target, order: order)))
        }
    }

    // MARK: - Undo

    /// The last action that can be taken back, shown with an Undo button for a few seconds.
    public struct UndoAction: Sendable {
        public enum Kind: Sendable {
            case reopen(TodoItem, order: [String])
            case restore(TodoItem, source: ThingsSource, target: ThingsSource, order: [String])
            case reorder(previous: [String], source: ThingsSource)
        }
        public let label: String
        public let kind: Kind
        let id = UUID()
    }

    public private(set) var undoAction: UndoAction?
    @ObservationIgnored public var undoTimeout: Duration = .seconds(8)

    private func offerUndo(_ action: UndoAction) {
        undoAction = action
        let timeout = undoTimeout
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            if self?.undoAction?.id == action.id { self?.undoAction = nil }
        }
    }

    public func dismissUndo() { undoAction = nil }

    /// Takes back the last complete, cancel, trash or reorder.
    public func undo() async {
        guard let action = undoAction else { return }
        undoAction = nil
        switch action.kind {
        case let .reopen(item, order):
            if await perform({ try await self.client.reopen(id: item.id) }) {
                await refresh()
                restoreOrder(order)
            }
        case let .restore(item, source, target, order):
            if await perform({ try await self.client.restore(id: item.id, to: target) }) {
                await refresh()
                if source == settings.source { restoreOrder(order) }
            }
        case let .reorder(previous, source):
            if source == settings.source { restoreOrder(previous) }
        }
    }

    /// Puts the list back in `ids` order (where ThingsBar can reorder), syncing to Things.
    private func restoreOrder(_ ids: [String]) {
        guard canReorder else { return }
        let current = items.map(\.id)
        let wanted = ids.filter(current.contains) + current.filter { !ids.contains($0) }
        guard wanted != current else { return }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        items = wanted.compactMap { byID[$0] }
        hasPendingOrder = true
        scheduleOrderSync()
    }

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

    public func reveal(_ item: TodoItem) async {
        await perform { try await self.client.reveal(id: item.id) }
    }

    /// Hides the row immediately; puts it back if Things refuses.
    /// When a row last disappeared: the row below slides under the pointer, so the UI
    /// briefly ignores checkbox clicks to stop a double click completing it too.
    public private(set) var lastRemoval: Date?

    /// `onSuccess` runs as soon as Things confirms, before the re-read, so Undo shows at once.
    @discardableResult
    private func removeOptimistically(_ item: TodoItem, _ action: @escaping () async throws -> Void,
                                      onSuccess: () -> Void = {}) async -> Bool {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        lastRemoval = Date()
        pendingIDs.insert(item.id)
        items.remove(at: index)
        let ok = await perform(action)
        pendingIDs.remove(item.id)
        if ok { onSuccess() } else { items.insert(item, at: min(index, items.count)) }
        await refresh()
        return ok
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
