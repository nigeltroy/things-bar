import Foundation

/// Builds Things URL-scheme (v2) commands. https://culturedcode.com/things/support/articles/2803573/
public enum ThingsURL {
    /// Percent-encodes everything except RFC 3986 unreserved characters, so
    /// `&`, `+`, `=`, `#` and newlines in titles survive intact.
    static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(.init(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func make(_ command: String, _ params: [(String, String)]) -> URL {
        let query = params.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        return URL(string: "things:///\(command)" + (query.isEmpty ? "" : "?\(query)"))!
    }

    static func dateString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// `add` puts the to-do in the right place for each source kind.
    public static func add(_ draft: TodoDraft, to source: ThingsSource, calendar: Calendar = .current) -> URL {
        var p: [(String, String)] = [("title", draft.title)]
        if !draft.notes.isEmpty { p.append(("notes", draft.notes)) }
        var tags = draft.tags
        switch source.kind {
        case .project, .area:
            p.append(("list-id", source.identifier))
        case .tag:
            if !tags.contains(source.identifier) { tags.append(source.identifier) }
        case .list:
            switch source.identifier {
            case ThingsSource.today.identifier: p.append(("when", "today"))
            case ThingsSource.anytime.identifier: p.append(("when", "anytime"))
            case ThingsSource.someday.identifier: p.append(("when", "someday"))
            case ThingsSource.upcoming.identifier: p.append(("when", "tomorrow"))
            default: break // Inbox is Things' default destination
            }
        }
        if !tags.isEmpty { p.append(("tags", tags.joined(separator: ","))) }
        if let deadline = draft.deadline { p.append(("deadline", dateString(deadline, calendar: calendar))) }
        return make("add", p)
    }

    public static func update(id: String, changes: TodoChanges, authToken: String, calendar: Calendar = .current) -> URL {
        var p: [(String, String)] = [("auth-token", authToken), ("id", id)]
        if let title = changes.title { p.append(("title", title)) }
        if let notes = changes.notes { p.append(("notes", notes)) }
        if let tags = changes.tags { p.append(("tags", tags.joined(separator: ","))) }
        if let deadline = changes.deadline { p.append(("deadline", deadline.map { dateString($0, calendar: calendar) } ?? "")) }
        if let when = changes.when { p.append(("when", when.rawValue)) }
        return make("update", p)
    }

    public static func show(id: String) -> URL { make("show", [("id", id)]) }

    /// A token check that can't change anything: `update` of a to-do ID that doesn't
    /// exist, replying to `thingsbar://token-check` with `x-success` or `x-error`.
    public static func tokenCheck(authToken: String, requestID: String) -> URL {
        let reply = "thingsbar://token-check?request=\(requestID)"
        return make("update", [("auth-token", authToken), ("id", "thingsbar-token-check-\(requestID)"),
                               ("x-success", reply + "&result=success"), ("x-error", reply + "&result=error")])
    }
}
