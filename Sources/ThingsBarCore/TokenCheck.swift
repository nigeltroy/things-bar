import Foundation

/// Whether Things accepts an auth token, from its reply to `ThingsURL.tokenCheck`.
public enum TokenCheck: Equatable, Sendable {
    case valid
    case invalid(String)

    public static let rejected = "Things didn't accept this token. Check that Enable Things URLs is on in Things → Settings → General, and that the whole token was copied."

    /// `result` is "success" or "error"; nil means Things never replied, which is what
    /// it does for a wrong token or with Things URLs turned off.
    public static func interpret(result: String?, errorCode: String?, errorMessage: String?) -> TokenCheck {
        switch result {
        case "success": return .valid
        // -12: the (deliberately nonexistent) to-do wasn't found, so the token was accepted.
        case "error" where errorCode == "-12": return .valid
        case "error": return .invalid(errorMessage.map { "Things: \($0)" } ?? rejected)
        default: return .invalid(rejected)
        }
    }
}
