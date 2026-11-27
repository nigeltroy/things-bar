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
        MenuBarTitle.make(top: topItem, remaining: visibleItems.count, settings: settings)
    }

    @ObservationIgnored public let client: ThingsClient
    @ObservationIgnored private let persistence: SettingsPersisting
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

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
            async let cat = client.catalog()
            async let todos = client.todos(in: source)
            let (newCatalog, newItems) = try await (cat, todos)
            catalog = newCatalog
            guard source == settings.source else { return } // source changed mid-read
            items = newItems
            errorMessage = nil
            lastRefresh = Date()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func dismissError() { errorMessage = nil }
}
