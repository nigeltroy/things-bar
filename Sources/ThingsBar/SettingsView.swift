import ServiceManagement
import SwiftUI
import ThingsBarCore

/// Settings shown inside the panel (no separate window): a back button returns
/// to the list, as when drilling into a Control Center module. Changes apply
/// immediately; there is no Save step except for the auth token.
struct SettingsPage: View {
    @Bindable var store: TodoStore
    let state: PanelState
    let tokenStore: TokenStoring

    @State private var tokenDraft = ""
    @State private var tokenMessage: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    listSection
                    menuBarSection
                    filterSection
                    generalSection
                    thingsSection
                    keyboardSection
                    Text("ThingsBar \(ThingsBarInfo.version)")
                        .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                        .padding(.vertical, 12)
                }
                .padding(.horizontal, Theme.edgeInset)
            }
            .frame(maxHeight: 500)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(SoftScrollEdges())
        }
        .task { await store.refresh() }
        .onAppear { tokenDraft = tokenStore.token ?? "" }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button { state.route = .list } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("Settings").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 6).frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverFillButtonStyle())
            .help("Back to the list (Esc)")
            Spacer()
        }
        .padding(.leading, Theme.edgeInset + 4).padding(.trailing, Theme.edgeInset + 2)
        .padding(.top, 10).padding(.bottom, 4)
    }

    // MARK: Sections

    private var listSection: some View {
        SettingsSection("List") {
            SettingsRow("Show to-dos from") {
                Menu(store.settings.source.name) {
                    sourceGroup("Lists", store.catalog.lists)
                    sourceGroup("Projects", store.catalog.projects)
                    sourceGroup("Areas", store.catalog.areas)
                    sourceGroup("Tags", store.catalog.tags)
                }
                .menuStyle(.button).buttonStyle(.plain)
                .modifier(ValueChip())
            }
        }
    }

    @ViewBuilder private func sourceGroup(_ title: String, _ sources: [ThingsSource]) -> some View {
        if !sources.isEmpty {
            Section(title) {
                ForEach(sources) { source in
                    Toggle(source.name, isOn: Binding(get: { store.settings.source == source },
                                                      set: { if $0 { store.settings.source = source } }))
                }
            }
        }
    }

    private var menuBarSection: some View {
        SettingsSection("Menu bar") {
            SettingsRow("To-dos shown") {
                Picker("", selection: $store.settings.menuBarItemCount) {
                    Text("1").tag(1); Text("2").tag(2); Text("3").tag(3)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            }
            SettingsRow("Length of each") {
                Menu("\(store.settings.menuBarTitleLength) characters") {
                    ForEach([16, 24, 32, 48, 64], id: \.self) { n in
                        Toggle("\(n) characters", isOn: Binding(get: { store.settings.menuBarTitleLength == n },
                                                               set: { if $0 { store.settings.menuBarTitleLength = n } }))
                    }
                }
                .menuStyle(.button).buttonStyle(.plain)
                .modifier(ValueChip())
            }
            SettingsToggle("Show how many remain", isOn: $store.settings.showCountInMenuBar)
            PreviewLine(text: store.menuBarTitle)
        }
    }

    private var filterSection: some View {
        SettingsSection("Filters") {
            SettingsRow("Only with tags") { tagMenu(selection: $store.settings.filter.includeTags, emptyLabel: "Any") }
            SettingsRow("Hide tags") { tagMenu(selection: $store.settings.filter.excludeTags, emptyLabel: "None") }
            SettingsToggle("Only with a deadline", isOn: $store.settings.filter.onlyWithDeadline)
            SettingsToggle("Hide scheduled for later", isOn: $store.settings.filter.hideScheduledLater)
            SettingsRow("Contains") {
                TextField("", text: $store.settings.filter.searchText, prompt: Text("Any text").foregroundStyle(Theme.textMuted))
                    .textFieldStyle(.plain).font(.system(size: 12)).multilineTextAlignment(.trailing)
                    .frame(width: 130)
                    .modifier(ValueChip())
            }
            if store.settings.filter.isActive {
                HStack {
                    Spacer()
                    Button("Clear filters") { store.settings.filter = TodoFilter() }.buttonStyle(SoftButtonStyle())
                }
                .padding(.horizontal, Theme.textInset).padding(.vertical, 4)
            }
        }
    }

    private func tagMenu(selection: Binding<[String]>, emptyLabel: String) -> some View {
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
        .menuStyle(.button).buttonStyle(.plain)
        .modifier(ValueChip())
    }

    private var generalSection: some View {
        SettingsSection("General") {
            SettingsRow("Appearance") {
                Picker("", selection: $store.settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            }
            SettingsToggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            if let loginError { Note(text: loginError) }
            SettingsRow("Quit ThingsBar", onLabelTap: { NSApplication.shared.terminate(nil) }) {
                Text("⌘Q").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
            .accessibilityAddTraits(.isButton)
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

    private var thingsSection: some View {
        SettingsSection("Things auth token") {
            HStack(spacing: 6) {
                SecureField("", text: $tokenDraft, prompt: Text("Paste token").foregroundStyle(Theme.textMuted))
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fieldFill))
                    .onSubmit(saveToken)
                Button("Save", action: saveToken)
                    .buttonStyle(SoftButtonStyle(prominent: true))
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespaces) == (tokenStore.token ?? ""))
            }
            .padding(.horizontal, Theme.textInset).padding(.vertical, 4)
            Note(text: tokenMessage ?? (store.hasAuthToken
                ? "Saved in your Keychain. Needed to edit, schedule and reorder Today."
                : "Needed to edit, schedule and reorder Today. In Things: Settings → General → Enable Things URLs → Manage."))
        }
    }

    private var keyboardSection: some View {
        SettingsSection("Keyboard") {
            ForEach([("New to-do", "⌘N"), ("Move to-do under the pointer", "⌘↑  ⌘↓"), ("Move to top or bottom", "⌥⌘↑  ⌥⌘↓"),
                     ("Edit", "Double-click"), ("Settings", "⌘,"), ("Back or close", "Esc")], id: \.0) { label, keys in
                HStack {
                    Text(label).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(keys).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, Theme.textInset).frame(height: 22)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func saveToken() {
        do {
            try tokenStore.setToken(tokenDraft)
            store.hasAuthToken = tokenStore.token != nil
            tokenMessage = tokenStore.token == nil ? "Token removed." : "Token saved to your Keychain."
        } catch {
            tokenMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

// MARK: - Building blocks

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: title)
            content
        }
        .padding(.bottom, 6)
    }
}

/// Label on the left, control on the right, 30 pt tall, hover fill only.
struct SettingsRow<Control: View>: View {
    let label: String
    var onLabelTap: (() -> Void)?
    @ViewBuilder let control: Control
    @State private var hovering = false
    init(_ label: String, onLabelTap: (() -> Void)? = nil, @ViewBuilder control: () -> Control) {
        self.label = label; self.onLabelTap = onLabelTap; self.control = control()
    }

    var body: some View {
        HStack(spacing: 8) {
            // Only the label area is a tap target, so clicking the control itself
            // (e.g. a switch) is handled once, by the control.
            HStack {
                Text(label).font(.system(size: 13)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture { onLabelTap?() }
            control
        }
        .padding(.horizontal, Theme.textInset).frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: Theme.rowCorner).fill(hovering ? Theme.hoverFill : .clear))
        .onHover { h in withAnimation(Theme.hoverAnimation) { hovering = h } }
    }
}

struct SettingsToggle: View {
    let label: String
    @Binding var isOn: Bool
    init(_ label: String, isOn: Binding<Bool>) { self.label = label; self._isOn = isOn }

    var body: some View {
        SettingsRow(label, onLabelTap: { isOn.toggle() }) {
            Toggle(label, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                .tint(Theme.textSecondary)
                .focusEffectDisabled()
        }
    }
}

/// A quiet capsule around a menu or field value.
struct ValueChip: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(Theme.fieldFill))
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 170, alignment: .trailing)
    }
}

struct Note: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.textInset).padding(.vertical, 3)
    }
}

/// Shows what the menu bar will read with the current settings.
struct PreviewLine: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "menubar.rectangle").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.textInset).padding(.vertical, 4)
        .accessibilityLabel("Menu bar preview: \(text)")
    }
}

struct HoverFillButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6).fill(configuration.isPressed ? Theme.strongFill : hovering ? Theme.hoverFill : .clear))
            .onHover { hovering = $0 }
    }
}

/// Tahoe's soft fade where content scrolls under the panel's edges (macOS 26+).
struct SoftScrollEdges: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .vertical)
        } else {
            content
        }
    }
}
