import Foundation

/// Reordering without a reorder API.
///
/// Things exposes no way to set a to-do's position. It does have a reliable
/// "move to top" in two lists (verified on Things 3.25):
/// - Today: rescheduling This Evening → Today puts a to-do first.
/// - Inbox: moving a to-do to another list and back puts it first.
/// Any order can be built from repeated moves to the top, so ThingsBar sends the
/// fewest moves that turn Things' order into the order the user dropped.
public enum ReorderPlan {
    /// Lists whose order ThingsBar can change in Things.
    public static func isSupported(in source: ThingsSource) -> Bool {
        source == .today || source == .inbox
    }

    /// IDs to move to the top, in this order, so that `current` becomes `desired`.
    ///
    /// The longest tail of `desired` that already appears in `current`'s order stays
    /// put; everything before it is moved, last first. Only IDs present in both lists
    /// are considered.
    public static func moveToTopSequence(from current: [String], to desired: [String]) -> [String] {
        let common = Set(current).intersection(desired)
        let cur = current.filter(common.contains)
        let des = desired.filter(common.contains)
        var i = des.count - 1, j = cur.count - 1
        while i >= 0 {
            while j >= 0 && cur[j] != des[i] { j -= 1 }
            guard j >= 0 else { break }
            i -= 1; j -= 1
        }
        return i >= 0 ? Array(des[0...i].reversed()) : []
    }

    /// Simulates moving each ID to the top (for tests and the in-memory client).
    public static func apply(_ moves: [String], to order: [String]) -> [String] {
        moves.reduce(order) { list, id in [id] + list.filter { $0 != id } }
    }

    /// The full list's new order after dragging `id` into `gap` (0…visible.count) of the
    /// visible (filtered) list. Hidden to-dos keep their places relative to their
    /// neighbours. Returns nil when the drop doesn't change anything.
    public static func moveVisible(id: String, toGap gap: Int, visible: [String], all: [String]) -> [String]? {
        guard let from = visible.firstIndex(of: id), all.contains(id), (0...visible.count).contains(gap),
              gap != from, gap != from + 1 else { return nil }
        var rest = visible
        rest.remove(at: from)
        let target = gap > from ? gap - 1 : gap
        var full = all.filter { $0 != id }
        if target < rest.count, let anchor = full.firstIndex(of: rest[target]) {
            full.insert(id, at: anchor)                       // just above the row it was dropped on
        } else if let last = rest.last, let anchor = full.firstIndex(of: last) {
            full.insert(id, at: anchor + 1)                   // just below the last visible row
        } else {
            full.insert(id, at: 0)
        }
        return full
    }

    /// Drop target while dragging the row at `from` with the pointer at `y`: the gap
    /// (0…count) before the first row whose middle is below the pointer. nil when the
    /// row would land where it already is, so no indicator is shown.
    public static func dropGap(pointerY y: Double, rowMidYs: [Double], from: Int) -> Int? {
        let gap = rowMidYs.firstIndex { y < $0 } ?? rowMidYs.count
        return gap == from || gap == from + 1 ? nil : gap
    }
}
