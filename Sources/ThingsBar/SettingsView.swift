import ServiceManagement
import SwiftUI
import ThingsBarCore

struct SettingsView: View {
    @Bindable var store: TodoStore
    let tokenStore: TokenStoring

    @State private var tokenDraft = ""
    @State private var tokenMessage: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            sourceSection
            filterSection
            menuBarSection
            thingsSection
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task { await store.refresh() }
        .onAppear { tokenDraft = tokenStore.token ?? "" }
    }

    // MARK: Source

    private var sourceSection: some View {
        Section {
            Picker("List", selection: $store.settings.source) {
                group("Lists", store.catalog.lists)
                group("Projects", store.catalog.projects)
                group("Areas", store.catalog.areas)
                group("Tags", store.catalog.tags)
                if !allSources.contains(store.settings.source) {
                    Text("\(store.settings.source.name) (missing)").tag(store.settings.source)
                }
            }
        } header: {
            Text("Show to-dos from")
        } footer: {
            Text("The first to-do, in Things' order, appears in the menu bar.").foregroundStyle(.secondary)
        }
    }

    private var allSources: [ThingsSource] {
        store.catalog.lists + store.catalog.projects + store.catalog.areas + store.catalog.tags
    }

    @ViewBuilder private func group(_ title: String, _ sources: [ThingsSource]) -> some View {
        if !sources.isEmpty {
            Section(title) {
                ForEach(sources) { Text($0.name).tag($0) }
            }
        }
    }

    // MARK: Filters

    private var filterSection: some View {
        Section("Filters") {
            tagMenu("Only with tags", selection: $store.settings.filter.includeTags, emptyLabel: "Any")
            tagMenu("Hide tags", selection: $store.settings.filter.excludeTags, emptyLabel: "None")
            Toggle("Only to-dos with a deadline", isOn: $store.settings.filter.onlyWithDeadline)
            Toggle("Hide to-dos scheduled for later", isOn: $store.settings.filter.hideScheduledLater)
            TextField("Title or notes contain", text: $store.settings.filter.searchText, prompt: Text("Anything"))
            if store.settings.filter.isActive {
                Button("Clear filters") { store.settings.filter = TodoFilter() }
            }
        }
    }

    private func tagMenu(_ title: String, selection: Binding<[String]>, emptyLabel: String) -> some View {
        LabeledContent(title) {
            Menu(selection.wrappedValue.isEmpty ? emptyLabel : selection.wrappedValue.joined(separator: ", ")) {
                if store.catalog.tagNames.isEmpty { Text("No tags in Things") }
                ForEach(store.catalog.tagNames, id: \.self) { tag in
                    Toggle(tag, isOn: Binding(
                        get: { selection.wrappedValue.contains(tag) },
                        set: { on in
                            selection.wrappedValue.removeAll { $0 == tag }
                            if on { selection.wrappedValue.append(tag) }
                        }))
                }
            }
            .fixedSize()
        }
    }

    // MARK: Menu bar

    private var menuBarSection: some View {
        Section("Menu bar") {
            Stepper("Title length: \(store.settings.menuBarTitleLength) characters",
                    value: $store.settings.menuBarTitleLength, in: 12...80, step: 4)
            Toggle("Show how many to-dos remain", isOn: $store.settings.showCountInMenuBar)
            Picker("Refresh every", selection: $store.settings.refreshSeconds) {
                Text("15 seconds").tag(15)
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
                Text("5 minutes").tag(300)
            }
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: Things

    private var thingsSection: some View {
        Section {
            HStack {
                SecureField("Auth token", text: $tokenDraft, prompt: Text("Paste token"))
                Button("Save") { saveToken() }
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespaces) == (tokenStore.token ?? ""))
            }
            if let tokenMessage { Text(tokenMessage).font(.caption).foregroundStyle(.secondary) }
        } header: {
            Text("Things")
        } footer: {
            Text("Needed to edit to-dos. In Things: Settings → General → Enable Things URLs → Manage. Stored in your Keychain.")
                .foregroundStyle(.secondary)
        }
    }

    private func saveToken() {
        do {
            try tokenStore.setToken(tokenDraft)
            tokenMessage = tokenStore.token == nil ? "Token removed." : "Token saved to Keychain."
        } catch {
            tokenMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

/// Hosts SettingsView in a regular window (menu bar apps have no Settings menu).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: TodoStore
    private let tokenStore: TokenStoring

    init(store: TodoStore, tokenStore: TokenStoring) {
        self.store = store; self.tokenStore = tokenStore
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store, tokenStore: tokenStore)))
            w.title = "ThingsBar Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
