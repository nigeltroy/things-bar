import SwiftUI
import ThingsBarCore

struct PopoverView: View {
    let store: TodoStore
    var openSettings: () -> Void = {}
    @State private var editingID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            AddTodoField(store: store)
                .padding(.horizontal, 12).padding(.bottom, 10)
            if let error = store.errorMessage {
                ErrorBanner(message: error, dismiss: store.dismissError)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            list
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 360)
        .background(Theme.background)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(store.settings.source.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if store.settings.filter.isActive {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    .help("Filters are active")
            }
            Spacer()
            if store.isLoading { ProgressView().controlSize(.mini) }
            Text("\(store.visibleItems.count)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    @ViewBuilder private var list: some View {
        if store.visibleItems.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.system(size: 22)).foregroundStyle(Theme.textTertiary)
                Text(store.isLoading && store.lastRefresh == nil ? "Loading…" : "Nothing to do here")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 28)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(store.visibleItems.enumerated()), id: \.element.id) { index, item in
                        if editingID == item.id {
                            TodoEditor(store: store, item: item) { editingID = nil }
                        } else {
                            TodoRow(store: store, item: item, isTop: index == 0) { editingID = item.id }
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            IconButton(systemName: "gearshape", help: "Settings… (⌘,)", action: openSettings)
                .keyboardShortcut(",", modifiers: .command)
            IconButton(systemName: "arrow.clockwise", help: "Refresh (⌘R)") { Task { await store.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .padding(.trailing, 6)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}

// MARK: - Add

struct AddTodoField: View {
    let store: TodoStore
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: store.isAdding ? "hourglass" : "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(focused ? Theme.accent : Theme.textTertiary)
                .frame(width: 18)
            TextField("", text: $title, prompt: Text("New to-do in \(store.settings.source.name)").foregroundStyle(Theme.textTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .disabled(store.isAdding)
                .onSubmit(submit)
            Button("") { focused = true }
                .keyboardShortcut("n", modifiers: .command)
                .buttonStyle(.plain).frame(width: 0, height: 0).opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(focused ? Theme.accent.opacity(0.5) : Theme.border))
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
    @State private var hovering = false
    @State private var checked = false

    private var pending: Bool { store.pendingIDs.contains(item.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Checkbox(checked: checked) { completeWithBeat() }
                .disabled(pending)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.system(size: 13, weight: isTop ? .medium : .regular))
                    .foregroundStyle(checked ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(checked, color: Theme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                MetaLine(item: item, catalog: store.catalog)
            }
            Spacer(minLength: 4)
            if hovering && !pending {
                HStack(spacing: 0) {
                    IconButton(systemName: "pencil", help: "Edit", action: edit)
                    MoreMenu(store: store, item: item)
                }
            } else if pending {
                ProgressView().controlSize(.mini).padding(.top, 2)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Theme.corner)
            .fill(hovering ? Theme.surface : (isTop ? Theme.accentSoft : .clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: edit)
        .contextMenu { TodoActions(store: store, item: item, edit: edit) }
        .help(item.notes)
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
                Circle().strokeBorder(checked || hovering ? Theme.accent : Theme.textTertiary, lineWidth: 1.5)
                if checked {
                    Circle().fill(Theme.accent)
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.background)
                } else if hovering {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.accent.opacity(0.7))
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Complete")
    }
}

struct MetaLine: View {
    let item: TodoItem
    let catalog: SourceCatalog

    var body: some View {
        let project = catalog.projectName(for: item.projectID) ?? catalog.areaName(for: item.areaID)
        if project != nil || item.deadline != nil || !item.tags.isEmpty || !item.notes.isEmpty {
            HStack(spacing: 8) {
                if let project {
                    Label(project, systemImage: "circle.dashed").labelStyle(.titleOnly)
                        .foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                if let deadline = item.deadline {
                    Label(DeadlineFormat.string(deadline), systemImage: "flag.fill")
                        .foregroundStyle(DeadlineFormat.isOverdue(deadline) ? Theme.danger : Theme.deadline)
                        .lineLimit(1)
                }
                if !item.tags.isEmpty {
                    Text(item.tags.joined(separator: " · ")).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                if !item.notes.isEmpty {
                    Image(systemName: "note.text").foregroundStyle(Theme.textTertiary)
                }
            }
            .font(.system(size: 11))
            .labelStyle(CompactLabelStyle())
        }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.font(.system(size: 9)); configuration.title }
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

    var body: some View {
        Menu {
            TodoActions(store: store, item: item, edit: nil)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }
}

struct TodoActions: View {
    let store: TodoStore
    let item: TodoItem
    let edit: (() -> Void)?

    var body: some View {
        if let edit { Button("Edit…", action: edit) }
        Button("Open in Things") { Task { await store.reveal(item) } }
        if store.canMoveToTop && store.items.first?.id != item.id {
            Button("Move to Top") { Task { await store.moveToTop(item) } }
        }
        Menu("When") {
            ForEach(WhenOption.allCases, id: \.self) { when in
                Button(when.label) { Task { await store.update(item, changes: TodoChanges(when: when)) } }
            }
        }
        .disabled(!store.hasAuthToken)
        Divider()
        Button("Complete") { Task { await store.complete(item) } }
        Button("Cancel To-Do") { Task { await store.cancel(item) } }
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
            HStack(spacing: 10) {
                Toggle(isOn: $hasDeadline) { Label("Deadline", systemImage: "flag") }
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
                    .font(.system(size: 11)).foregroundStyle(Theme.deadline)
            }
            HStack {
                Spacer()
                Button("Cancel", action: done).buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction)
                Button(saving ? "Saving…" : "Save", action: save)
                    .buttonStyle(SoftButtonStyle(prominent: true))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(saving || !store.hasAuthToken || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.border))
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
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.surfaceHover))
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
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger).font(.system(size: 11))
            Text(message).font(.system(size: 11)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            IconButton(systemName: "xmark", help: "Dismiss", action: dismiss)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.danger.opacity(0.12)))
    }
}
