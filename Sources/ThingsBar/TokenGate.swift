import SwiftUI
import ThingsBarCore

enum TokenGate {
    static let prompt = "Enter Things auth token to use ThingsBar"
    static let whereToFind = "In Things: Settings → General → Enable Things URLs → Manage. Copy the auth token and paste it here."
    static let revoked = "Things no longer accepts the saved token. Paste the current one from Things → Settings → General → Enable Things URLs → Manage."

    /// Checks `draft` with Things and, if Things accepts it, saves it and opens the list.
    /// Returns an error to show, or nil on success. Nothing is saved for a rejected token.
    @MainActor
    static func submit(_ draft: String, store: TodoStore, tokenStore: TokenStoring, state: PanelState) async -> String? {
        let token = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        if case .invalid(let message) = await state.verifyToken(token) { return message }
        do {
            try tokenStore.setToken(token)
        } catch {
            return "Couldn't save the token: \(error.localizedDescription)"
        }
        state.gateMessage = nil
        state.route = .list
        store.hasAuthToken = true
        Task { await store.refresh() }
        return nil
    }
}

/// The whole panel while no auth token is saved: ThingsBar needs the token to work at
/// all, so entering it is the only thing to do. Things isn't read until it's saved.
struct TokenGatePage: View {
    let store: TodoStore
    let tokenStore: TokenStoring
    let state: PanelState
    @State private var draft = ""
    @State private var error: String?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(TokenGate.prompt)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.edgeInset + Theme.textInset).padding(.top, 12).padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            TokenField(draft: $draft, savedToken: nil, autofocus: true, checking: checking, save: save)
                .padding(.horizontal, Theme.edgeInset)
            Note(text: error ?? state.gateMessage ?? TokenGate.whereToFind, emphasized: error != nil || state.gateMessage != nil)
                .padding(.horizontal, Theme.edgeInset).padding(.top, 4)
            HStack {
                Spacer()
                Button("Quit ThingsBar") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(FocusRingButtonStyle(shape: RoundedRectangle(cornerRadius: 4)))
                    .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, Theme.edgeInset + Theme.textInset).padding(.top, 2).padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .onChange(of: draft) { _, _ in error = nil }
    }

    private func save() {
        checking = true
        Task {
            error = await TokenGate.submit(draft, store: store, tokenStore: tokenStore, state: state)
            checking = false
        }
    }
}

/// Secure token entry with a Save button, used by the gate and by Settings. Save
/// checks the token with Things first ("Checking…").
struct TokenField: View {
    @Binding var draft: String
    /// The token already saved, if any: Save is enabled only for a different value.
    let savedToken: String?
    var autofocus = false
    var checking = false
    let save: () -> Void
    @FocusState private var focused: Bool
    @State private var revealed = false

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !checking && !trimmed.isEmpty && trimmed != (savedToken ?? "") }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Group {
                    if revealed {
                        TextField("Things auth token", text: $draft, prompt: Text("")).placeholder("Paste auth token", when: draft.isEmpty)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("Things auth token", text: $draft, prompt: Text("")).placeholder("Paste auth token", when: draft.isEmpty)
                            .font(.system(size: 12))
                    }
                }
                .textFieldStyle(.plain).tint(Theme.textPrimary) /* gray caret */
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .onSubmit { if canSave { save() } }
                .accessibilityLabel("Things auth token")
                // Lets people check a paste (a missing or extra character is the usual mistake).
                Button { revealed.toggle() } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(FocusRingButtonStyle(shape: RoundedRectangle(cornerRadius: 4)))
                .help(revealed ? "Hide token" : "Show token")
                .accessibilityLabel(revealed ? "Hide token" : "Show token")
            }
            .padding(.leading, 8).padding(.trailing, 3).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Theme.fieldBorderFocused : Theme.fieldBorder))
            Button(checking ? "Checking…" : "Save") { save() }
                .buttonStyle(SoftButtonStyle(prominent: true))
                .disabled(!canSave)
        }
        .padding(.horizontal, Theme.textInset).padding(.vertical, 4)
        .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
    }
}
