import SwiftUI
import ThingsBarCore

/// What the panel is showing. Settings live inside the panel, Control Center style.
@MainActor @Observable
final class PanelState {
    enum Route { case list, settings }
    var route: Route = .list
    var editingID: String?

    /// Esc: leave the editor or settings first; returns false when there's nothing to back out of.
    func back() -> Bool {
        if editingID != nil { editingID = nil; return true }
        if route == .settings { route = .list; return true }
        return false
    }
}

struct PanelView: View {
    let store: TodoStore
    let state: PanelState
    let tokenStore: TokenStoring
    var openThings: () -> Void = {}
    var sizeChanged: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            switch state.route {
            case .list:
                ListPage(store: store, state: state, openThings: openThings)
                    .transition(pageTransition(edge: .leading))
            case .settings:
                SettingsPage(store: store, state: state, tokenStore: tokenStore)
                    .transition(pageTransition(edge: .trailing))
            }
        }
        .frame(width: Theme.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: state.route)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in sizeChanged() }
        .background(KeyboardShortcuts(store: store, state: state))
    }

    private func pageTransition(edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

/// Invisible buttons that own the panel's keyboard shortcuts.
private struct KeyboardShortcuts: View {
    let store: TodoStore
    let state: PanelState
    var body: some View {
        ZStack {
            Button("") { state.route = state.route == .settings ? .list : .settings }.keyboardShortcut(",", modifiers: .command)
            Button("") { _ = state.back() }.keyboardShortcut("[", modifiers: .command)
            Button("") { Task { await store.refresh() } }.keyboardShortcut("r", modifiers: .command)
            Button("") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.plain).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}

// MARK: - List page

struct ListPage: View {
    let store: TodoStore
    let state: PanelState
    var openThings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            AddTodoField(store: store)
                .padding(.horizontal, Theme.edgeInset).padding(.bottom, 4)
            if let error = store.errorMessage {
                ErrorBanner(message: error, dismiss: store.dismissError)
                    .padding(.horizontal, Theme.edgeInset).padding(.bottom, 4)
            }
            TodoListView(store: store, state: state)
            Rectangle().fill(Theme.separator).frame(height: 1).padding(.horizontal, Theme.textInset + Theme.edgeInset)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(store.settings.source.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if store.settings.filter.isActive {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                    .help("Filters are on")
            }
            Spacer()
            Text("\(store.visibleItems.count)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .help("\(store.visibleItems.count) to-dos")
            IconButton(systemName: "gearshape", help: "Settings (⌘,)") { state.route = .settings }
        }
        .padding(.leading, Theme.edgeInset + Theme.textInset).padding(.trailing, Theme.edgeInset + 2)
        .padding(.top, 10).padding(.bottom, 6)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer()
            IconButton(systemName: "arrow.up.forward.app", help: "Open Things", action: openThings)
            IconButton(systemName: "power", help: "Quit ThingsBar (⌘Q)") { NSApplication.shared.terminate(nil) }
        }
        .padding(.leading, Theme.edgeInset + Theme.textInset).padding(.trailing, Theme.edgeInset + 2)
        .padding(.vertical, 5)
    }

    private var statusText: String {
        if store.isSyncingOrder { return "Saving order to Things…" }
        if store.isLoading && store.lastRefresh == nil { return "Reading Things…" }
        if store.canReorder { return "Drag to reorder" }
        return store.reorderUnavailableReason ?? "Synced with Things"
    }
}

// MARK: - List

struct TodoListView: View {
    let store: TodoStore
    let state: PanelState

    var body: some View {
        if store.visibleItems.isEmpty {
            EmptyStateView(loading: store.isLoading && store.lastRefresh == nil, filtered: store.settings.filter.isActive && !store.items.isEmpty)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(store.visibleItems.enumerated()), id: \.element.id) { index, item in
                        if state.editingID == item.id {
                            TodoEditor(store: store, item: item) { state.editingID = nil }
                                .padding(.vertical, 2)
                        } else {
                            TodoRow(store: store, item: item, isTop: index == 0) { state.editingID = item.id }
                        }
                    }
                }
                .padding(.horizontal, Theme.edgeInset).padding(.vertical, 2)
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: 440)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct EmptyStateView: View {
    let loading: Bool
    let filtered: Bool
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: loading ? "ellipsis" : "checkmark")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
            Text(loading ? "Reading Things…" : filtered ? "No to-dos match your filters" : "Nothing to do here")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

// MARK: - Add

struct AddTodoField: View {
    let store: TodoStore
    @State private var title = ""
    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(focused ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 16)
            TextField("", text: $title, prompt: Text("New To-Do").foregroundStyle(Theme.textTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .disabled(store.isAdding)
                .onSubmit(submit)
                .onExitCommand { if !title.isEmpty { title = "" } else { focused = false } }
            if store.isAdding {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16)
            } else if !title.isEmpty {
                Text("↩").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
            Button("") { focused = true }
                .keyboardShortcut("n", modifiers: .command)
                .buttonStyle(.plain).frame(width: 0, height: 0).opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.textInset).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: Theme.rowCorner)
            .fill(focused ? Theme.strongFill : hovering ? Theme.hoverFill : Theme.fieldFill))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onHover { h in withAnimation(Theme.hoverAnimation) { hovering = h } }
        .help("New to-do in \(store.settings.source.name) (⌘N)")
    }

    private func submit() {
        let text = title
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            if await store.add(TodoDraft(title: text)) { title = "" }
            focused = true
        }
    }
}

// MARK: - Row

struct TodoRow: View {
    let store: TodoStore
    let item: TodoItem
    let isTop: Bool
    let edit: () -> Void
    /// Self-test only: render the hover state without a mouse.
    var forceHover = false
    @State private var hoveringState = false
    @State private var checked = false

    private var hovering: Bool { hoveringState || forceHover }
    private var pending: Bool { store.pendingIDs.contains(item.id) }
    private static let actionsWidth: CGFloat = 52

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Checkbox(checked: checked) { completeWithBeat() }
                .disabled(pending)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.system(size: 13, weight: isTop ? .semibold : .regular))
                    .foregroundStyle(checked ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(checked, color: Theme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                MetaLine(item: item, catalog: store.catalog)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Fade the text's end under the hover actions instead of reflowing it.
            .mask(alignment: .trailing) {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .black.opacity(hovering ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 24)
                    Rectangle().fill(.black.opacity(hovering ? 0 : 1)).frame(width: Self.actionsWidth - 16)
                }
            }
        }
        .padding(.horizontal, Theme.textInset).padding(.vertical, 6)
        .frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: Theme.rowCorner).fill(hovering ? Theme.hoverFill : .clear))
        // Actions float over the row: showing them never changes the row's size.
        .overlay(alignment: .topTrailing) {
            Group {
                if pending {
                    ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 24, height: 24)
                } else {
                    HStack(spacing: 0) {
                        IconButton(systemName: "pencil", help: "Edit", action: edit)
                        MoreMenu(store: store, item: item, edit: edit)
                    }
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
                }
            }
            .padding(.top, 3).padding(.trailing, 4)
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Theme.hoverAnimation) { hoveringState = h } }
        .onTapGesture(count: 2, perform: edit)
        .contextMenu { TodoActions(store: store, item: item, edit: edit) }
        .help(item.notes)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            Button("Complete") { Task { await store.complete(item) } }
            Button("Edit", action: edit)
        }
    }

    /// Show the check for a moment so the completion is visible, then complete.
    private func completeWithBeat() {
        withAnimation(.easeOut(duration: 0.15)) { checked = true }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            await store.complete(item)
            checked = false
        }
    }
}

struct Checkbox: View {
    let checked: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(checked || hovering ? Theme.textSecondary : Theme.textTertiary, lineWidth: 1.25)
                if checked {
                    Circle().fill(Theme.textPrimary)
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                } else if hovering {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Complete")
        .accessibilityLabel("Complete")
    }
}

struct MetaLine: View {
    let item: TodoItem
    let catalog: SourceCatalog

    var body: some View {
        let parent = catalog.projectName(for: item.projectID) ?? catalog.areaName(for: item.areaID)
        if parent != nil || item.deadline != nil || !item.tags.isEmpty || !item.notes.isEmpty {
            HStack(spacing: 7) {
                if let deadline = item.deadline {
                    let overdue = DeadlineFormat.isOverdue(deadline)
                    Label(DeadlineFormat.string(deadline), systemImage: "flag.fill")
                        .foregroundStyle(overdue ? Theme.textPrimary : Theme.textSecondary)
                        .fontWeight(overdue ? .semibold : .regular)
                        .lineLimit(1)
                }
                if let parent {
                    Text(parent).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                if !item.tags.isEmpty {
                    Text(item.tags.joined(separator: " · ")).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                if !item.notes.isEmpty {
                    Image(systemName: "text.alignleft").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                }
            }
            .font(.system(size: 11))
            .labelStyle(CompactLabelStyle())
        }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.font(.system(size: 8)); configuration.title }
    }
}

enum DeadlineFormat {
    static func isOverdue(_ date: Date, now: Date = Date()) -> Bool {
        Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: now)
    }

    static func string(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        if days < 0 { return "\(-days)d overdue" }
        if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Actions menu

struct MoreMenu: View {
    let store: TodoStore
    let item: TodoItem
    let edit: () -> Void
    @State private var hovering = false

    var body: some View {
        Menu {
            TodoActions(store: store, item: item, edit: nil)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.hoverFill : .clear))
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("More")
        .accessibilityLabel("More actions")
    }
}

struct TodoActions: View {
    let store: TodoStore
    let item: TodoItem
    let edit: (() -> Void)?

    var body: some View {
        if let edit { Button("Edit…", action: edit) }
        Button("Open in Things") { Task { await store.reveal(item) } }
        if store.canReorder {
            let index = store.visibleItems.firstIndex(of: item) ?? 0
            let last = store.visibleItems.count - 1
            Divider()
            Button("Move to Top") { store.moveVisible(item, to: 0) }.disabled(index == 0)
            Button("Move Up") { store.moveVisible(item, to: index - 1) }.disabled(index == 0)
            Button("Move Down") { store.moveVisible(item, to: index + 1) }.disabled(index >= last)
            Button("Move to Bottom") { store.moveVisible(item, to: last) }.disabled(index >= last)
        }
        Divider()
        Menu("When") {
            ForEach(WhenOption.allCases, id: \.self) { when in
                Button(when.label) { Task { await store.update(item, changes: TodoChanges(when: when)) } }
            }
        }
        .disabled(!store.hasAuthToken)
        Button("Complete") { Task { await store.complete(item) } }
        Button("Cancel To-Do") { Task { await store.cancel(item) } }
        Divider()
        Button("Move to Trash", role: .destructive) { Task { await store.delete(item) } }
    }
}

// MARK: - Edit

struct TodoEditor: View {
    let store: TodoStore
    let item: TodoItem
    let done: () -> Void

    @State private var title: String
    @State private var notes: String
    @State private var tags: [String]
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var saving = false
    @FocusState private var titleFocused: Bool

    init(store: TodoStore, item: TodoItem, done: @escaping () -> Void) {
        self.store = store; self.item = item; self.done = done
        _title = State(initialValue: item.title)
        _notes = State(initialValue: item.notes)
        _tags = State(initialValue: item.tags)
        _hasDeadline = State(initialValue: item.deadline != nil)
        _deadline = State(initialValue: item.deadline ?? Calendar.current.startOfDay(for: Date()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $title, prompt: Text("Title").foregroundStyle(Theme.textTertiary))
                .textFieldStyle(.plain).font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary).focused($titleFocused)
            TextField("", text: $notes, prompt: Text("Notes").foregroundStyle(Theme.textTertiary), axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .lineLimit(1...6)
            HStack(spacing: 8) {
                Toggle(isOn: $hasDeadline) { Text("Deadline") }
                    .toggleStyle(.checkbox).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                if hasDeadline {
                    DatePicker("", selection: $deadline, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field).controlSize(.small)
                }
                Spacer()
                TagPicker(all: store.catalog.tagNames, selection: $tags)
            }
            if !store.hasAuthToken {
                Text("Add your Things auth token in Settings to save edits.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 6) {
                Spacer()
                Button("Cancel", action: done).buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction)
                Button(saving ? "Saving…" : "Save", action: save)
                    .buttonStyle(SoftButtonStyle(prominent: true))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(saving || !store.hasAuthToken || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.rowCorner + 1).fill(Theme.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: Theme.rowCorner + 1).strokeBorder(Theme.separator))
        .onAppear { titleFocused = true }
    }

    private func save() {
        saving = true
        let changes = TodoChanges(title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes, tags: tags,
                                  deadline: .some(hasDeadline ? deadline : nil))
        Task {
            let ok = await store.update(item, changes: changes)
            saving = false
            if ok { done() }
        }
    }
}

struct TagPicker: View {
    let all: [String]
    @Binding var selection: [String]

    var body: some View {
        Menu {
            if all.isEmpty { Text("No tags in Things") }
            ForEach(all, id: \.self) { tag in
                Toggle(tag, isOn: Binding(
                    get: { selection.contains(tag) },
                    set: { on in selection.removeAll { $0 == tag }; if on { selection.append(tag) } }))
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag").font(.system(size: 10))
                Text(selection.isEmpty ? "Tags" : selection.joined(separator: ", ")).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Theme.strongFill))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.textPrimary).font(.system(size: 12, weight: .medium))
                .padding(.top, 1)
            Text(message).font(.system(size: 11)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            IconButton(systemName: "xmark", help: "Dismiss", size: 18, action: dismiss)
        }
        .padding(.horizontal, Theme.textInset).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Theme.rowCorner).fill(Theme.strongFill))
    }
}
