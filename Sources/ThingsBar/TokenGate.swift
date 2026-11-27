import SwiftUI
import ThingsBarCore

enum TokenGate {
    static let prompt = "Enter Things auth token to use ThingsBar"
    static let whereToFind = "In Things: Settings → General → Enable Things URLs → Manage. Copy the auth token and paste it here."
}

/// The whole panel while no auth token is saved: ThingsBar needs the token to work at
/// all, so entering it is the only thing to do. Things isn't read until it's saved.
struct TokenGatePage: View {
    let store: TodoStore
    let tokenStore: TokenStoring
    var state: PanelState?
    @State private var draft = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ThingsBar")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.edgeInset + Theme.textInset).padding(.top, 12).padding(.bottom, 8)
            Text(TokenGate.prompt)
                .font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.edgeInset + Theme.textInset).padding(.bottom, 8)
            TokenField(draft: $draft, savedToken: nil, autofocus: true, save: save)
                .padding(.horizontal, Theme.edgeInset)
            Note(text: error ?? TokenGate.whereToFind)
                .padding(.horizontal, Theme.edgeInset).padding(.top, 4).padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func save() {
        do {
            try tokenStore.setToken(draft)
            guard tokenStore.token != nil else { return }
            error = nil
            state?.route = .list
            store.hasAuthToken = true
            Task { await store.refresh() }
        } catch {
            self.error = "Couldn't save the token: \(error.localizedDescription)"
        }
    }
}

/// Secure token entry with a Save button, used by the gate and by Settings.
struct TokenField: View {
    @Binding var draft: String
    /// The token already saved, if any: Save is enabled only for a different value.
    let savedToken: String?
    var autofocus = false
    let save: () -> Void
    @FocusState private var focused: Bool

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The gate can't save an empty token; Settings can (that removes it).
    private var canSave: Bool { trimmed != (savedToken ?? "") && (savedToken != nil || !trimmed.isEmpty) }

    var body: some View {
        HStack(spacing: 6) {
            SecureField("Things auth token", text: $draft, prompt: Text("")).placeholder("Paste auth token", when: draft.isEmpty)
                .textFieldStyle(.plain).tint(Theme.textPrimary) /* gray caret */
                .font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .padding(.horizontal, 8).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Theme.fieldBorderFocused : Theme.fieldBorder))
                .onSubmit { if canSave { save() } }
                .accessibilityLabel("Things auth token")
            Button("Save") { save() }
                .buttonStyle(SoftButtonStyle(prominent: true))
                .disabled(!canSave)
        }
        .padding(.horizontal, Theme.textInset).padding(.vertical, 4)
        .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
    }
}
