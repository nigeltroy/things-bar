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
    var updates: UpdateChecker?

    @State private var tokenDraft = ""
    @State private var tokenMessage: String?
    @State private var tokenError = false
    @State private var checkingToken = false
    @State private var confirmingRemove = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var filtersExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    // What to show, how the menu bar reads it, what unlocks editing, then the rest.
                    listSection
                    menuBarSection
                    thingsSection
                    generalSection
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
        .confirmationDialog("Remove the auth token?", isPresented: $confirmingRemove) {
            Button("Remove Token", role: .destructive, action: removeToken)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("ThingsBar stops working until you enter a token again. Things itself isn't affected.")
        }
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
                .grayFocusRing(cornerRadius: 11)
            }
            filterRows
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
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize().grayFocusRing()
            }
            SettingsRow("Width") {
                Picker("", selection: $store.settings.menuBarWidth) {
                    ForEach(AppSettings.MenuBarWidth.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize().grayFocusRing()
                .help("Titles are shortened to fit, so macOS never hides ThingsBar for lack of room")
            }
            SettingsToggle("Show how many remain", isOn: $store.settings.showCountInMenuBar)
            PreviewLine(text: store.menuBarTitle)
        }
    }

    /// Filters are a power feature: one summary row in the List section that expands.
    @ViewBuilder private var filterRows: some View {
        SettingsRow("Filters", onLabelTap: { withAnimation(Theme.motion(.snappy(duration: 0.2))) { filtersExpanded.toggle() } }) {
            HStack(spacing: 6) {
                Text(filterSummary).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .rotationEffect(.degrees(filtersExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Theme.motion(.snappy(duration: 0.2))) { filtersExpanded.toggle() } }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(filtersExpanded ? "Expanded" : "Collapsed")
        if filtersExpanded {
            VStack(spacing: 0) { filterControls }
                .padding(.leading, 10)
                .transition(.opacity)
        }
    }

    private var filterSummary: String {
        let f = store.settings.filter
        let count = [!f.includeTags.isEmpty, !f.excludeTags.isEmpty, f.onlyWithDeadline, f.hideScheduledLater,
                     !f.searchText.trimmingCharacters(in: .whitespaces).isEmpty].filter { $0 }.count
        return count == 0 ? "Off" : "\(count) on"
    }

    @ViewBuilder private var filterControls: some View {
        Group {
            SettingsRow("Only with tags") { tagMenu(selection: $store.settings.filter.includeTags, emptyLabel: "Any") }
            SettingsRow("Hide tags") { tagMenu(selection: $store.settings.filter.excludeTags, emptyLabel: "None") }
            SettingsToggle("Only with a deadline", isOn: $store.settings.filter.onlyWithDeadline)
            SettingsToggle("Hide scheduled for later", isOn: $store.settings.filter.hideScheduledLater)
            SettingsRow("Contains") {
                TextField("Contains", text: $store.settings.filter.searchText, prompt: Text("")).placeholder("Any text", when: store.settings.filter.searchText.isEmpty, alignment: .trailing)
                    .textFieldStyle(.plain).tint(Theme.textPrimary) /* gray caret */.font(.system(size: 12)).multilineTextAlignment(.trailing)
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
        .grayFocusRing(cornerRadius: 11)
    }

    private var generalSection: some View {
        SettingsSection("General") {
            SettingsRow("Appearance") {
                Picker("", selection: $store.settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize().grayFocusRing()
            }
            if let updates { UpdateRows(updates: updates, automatic: $store.settings.checkForUpdatesAutomatically) }
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
        SettingsSection("Things access") {
            TokenField(draft: $tokenDraft, savedToken: tokenStore.token, checking: checkingToken, save: saveToken)
            Note(text: tokenMessage ?? "Saved in your Keychain. To use a new token, paste it and Save; ThingsBar checks it with Things first.",
                 emphasized: tokenError)
            HStack {
                Spacer()
                Button("Remove Token…") { confirmingRemove = true }.buttonStyle(SoftButtonStyle())
            }
            .padding(.horizontal, Theme.textInset).padding(.vertical, 2)
        }
    }

    private var keyboardSection: some View {
        SettingsSection("Keyboard") {
            ForEach([("New to-do", "⌘N"), ("Highlight a to-do", "↑  ↓"), ("Complete it", "Space"), ("Edit it", "↩  or double-click"),
                     ("Move it to Trash", "⌘⌫"), ("Move it up or down", "⌘↑  ⌘↓"), ("Move it to top or bottom", "⌥⌘↑  ⌥⌘↓"), ("Undo complete, trash or reorder", "⌘Z"), ("Settings", "⌘,"), ("Back or close", "Esc")], id: \.0) { label, keys in
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
        checkingToken = true
        Task {
            let error = await TokenGate.submit(tokenDraft, store: store, tokenStore: tokenStore, state: state)
            state.route = .settings // submit opens the list; stay here
            tokenError = error != nil
            tokenMessage = error ?? "Token checked with Things and saved to your Keychain."
            checkingToken = false
        }
    }

    private func removeToken() {
        try? tokenStore.setToken(nil)
        tokenDraft = ""
        state.route = .list
        store.hasAuthToken = false // back to the token prompt
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
            Toggle(label, isOn: $isOn).labelsHidden().toggleStyle(GraySwitchStyle())
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
    /// Errors and warnings read in secondary, not muted, text.
    var emphasized = false
    var body: some View {
        Text(text)
            .font(.system(size: 11)).foregroundStyle(emphasized ? Theme.textPrimary : Theme.textMuted)
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
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6).fill(configuration.isPressed ? Theme.strongFill : hovering ? Theme.hoverFill : .clear))
            .overlay { if isFocused { RoundedRectangle(cornerRadius: 6).inset(by: -1).strokeBorder(Theme.focusRing, lineWidth: 1.5) } }
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

/// "Check for Updates" with its result, and the automatic-check switch.
struct UpdateRows: View {
    let updates: UpdateChecker
    @Binding var automatic: Bool
    var progress = UpdateActions.progress

    var body: some View {
        SettingsRow("Check for Updates", onLabelTap: { Task { await updates.check() } }) {
            switch updates.status {
            case .checking:
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 16, height: 16)
            case .available(let release):
                switch progress.phase {
                case .downloading, .installing:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 16, height: 16)
                        Text(progress.phase == .installing ? "Installing…" : "Downloading…")
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                case .idle, .failed:
                    Button(progress.phase == .idle ? "Install \(release.version)" : "Try Again") { UpdateActions.install(release) }
                        .buttonStyle(SoftButtonStyle(prominent: true))
                        .help("Downloads ThingsBar \(release.version), then quits, replaces and reopens ThingsBar")
                }
            case .upToDate:
                Text("Up to date").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            case .failed:
                Button("Try Again") { Task { await updates.check() } }.buttonStyle(SoftButtonStyle())
            case .idle:
                Button("Check Now") { Task { await updates.check() } }.buttonStyle(SoftButtonStyle())
            }
        }
        .accessibilityAddTraits(.isButton)
        if case .failed(let message) = progress.phase, case .available(let release) = updates.status {
            Note(text: "Couldn't install ThingsBar \(release.version). \(message)", emphasized: true)
            HStack {
                Button("Download in Browser") { UpdateActions.openInBrowser(release) }.buttonStyle(SoftButtonStyle())
                Spacer()
            }
            .padding(.horizontal, Theme.textInset)
        } else if case .available(let release) = updates.status {
            Note(text: "ThingsBar \(release.version) is available (you have \(updates.currentVersion)). Install downloads it, then quits ThingsBar, replaces it and reopens it.")
        } else if case .failed(let message) = updates.status {
            Note(text: "Couldn't check for updates. \(message)")
        }
        SettingsToggle("Check for updates automatically", isOn: $automatic)
    }
}

@MainActor
enum UpdateActions {
    /// Installs in place (Sparkle), set up by the app delegate. Nil in self-tests.
    @MainActor static var installer: ((ReleaseInfo) -> Void)?
    /// What the install is doing (the app delegate shares Sparkle's).
    @MainActor static var progress = InstallProgress()

    /// Downloads, quits, replaces ThingsBar and reopens it; the browser if that's unavailable.
    @MainActor static func install(_ release: ReleaseInfo) {
        if let installer { installer(release) } else { openInBrowser(release) }
    }

    /// Opens the DMG (the browser downloads it), or the release page if there's none.
    static func openInBrowser(_ release: ReleaseInfo) {
        NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
    }
}
