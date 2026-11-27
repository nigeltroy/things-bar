import Foundation

public enum ThingsError: Error, Equatable, LocalizedError, Sendable {
    /// macOS Automation permission denied (errAEEventNotPermitted, -1743).
    case automationDenied
    /// Things did not answer in time (errAETimeout, -1712).
    case timedOut
    /// Things isn't installed.
    case thingsNotInstalled
    /// Things isn't running (the client launches it and retries once).
    case thingsNotRunning
    /// The chosen list/project/area/tag no longer exists in Things.
    case sourceNotFound(String)
    /// Editing needs the Things URL auth token (Things → Settings → General → Enable Things URLs).
    case missingAuthToken
    /// A URL-scheme write was sent but Things never applied it (wrong token, URLs disabled...).
    case changeNotApplied
    case script(number: Int, message: String)
    case unexpectedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .automationDenied:
            "ThingsBar isn't allowed to control Things. Enable it in System Settings → Privacy & Security → Automation."
        case .timedOut:
            "Things didn't respond in time."
        case .thingsNotInstalled:
            "Things 3 isn't installed."
        case .thingsNotRunning:
            "Things isn't running."
        case let .sourceNotFound(name):
            "\u{201C}\(name)\u{201D} no longer exists in Things. Pick another list in Settings."
        case .missingAuthToken:
            "Add your Things URL auth token in Settings to edit to-dos."
        case .changeNotApplied:
            "Things didn't apply the change. Check that Things URLs are enabled and the auth token is correct."
        case let .script(number, message):
            "Things error \(number): \(message)"
        case let .unexpectedResponse(detail):
            "Unexpected response from Things: \(detail)"
        }
    }
}
