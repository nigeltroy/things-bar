import AppKit
import ThingsBarCore

/// Asks Things whether an auth token is valid, without changing anything (see
/// `ThingsURL.tokenCheck`). Things replies through the thingsbar:// URL scheme.
@MainActor
final class TokenVerifier {
    private var pending: [String: CheckedContinuation<TokenCheck, Never>] = [:]

    init() {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let comps = URLComponents(string: string), comps.host == "token-check" else { return }
        let q = Dictionary((comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        guard let id = q["request"], let cont = pending.removeValue(forKey: id) else { return }
        cont.resume(returning: TokenCheck.interpret(result: q["result"], errorCode: q["errorCode"], errorMessage: q["errorMessage"]))
    }

    /// Things answers a valid token within a moment; a wrong one gets no answer at all.
    func verify(_ token: String, timeout: Duration = .seconds(5)) async -> TokenCheck {
        let id = UUID().uuidString
        let url = ThingsURL.tokenCheck(authToken: token, requestID: id)
        return await withCheckedContinuation { cont in
            pending[id] = cont
            Task {
                do { try await WorkspaceURLOpener().open(url, activate: false) } catch {
                    if let c = pending.removeValue(forKey: id) { c.resume(returning: .invalid(error.localizedDescription)) }
                }
                try? await Task.sleep(for: timeout)
                if let c = pending.removeValue(forKey: id) {
                    c.resume(returning: TokenCheck.interpret(result: nil, errorCode: nil, errorMessage: nil))
                }
            }
        }
    }
}
