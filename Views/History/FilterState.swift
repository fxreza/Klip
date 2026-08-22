import Foundation

/// The inputs that decide which clipboard items the history list shows.
///
/// Kept as a plain value type with a pure `apply` so the filtering rules can be
/// unit-tested without a store, a window or SwiftUI (see `Tests/FilterStateTests.swift`).
struct FilterState: Equatable {
    /// Raw search field text (already debounced by the view model).
    var query: String
    /// Active tag chip filter, or nil.
    var tag: String?

    init(query: String = "", tag: String? = nil) {
        self.query = query
        self.tag = tag
    }

    /// Filter + order `items` for display.
    ///
    /// Rules (unchanged from the pre-split `computeFilteredItems`):
    /// 1. If a tag filter is active, keep only items carrying that tag.
    /// 2. A non-empty query that does not start with `#` matches `.text` items
    ///    whose `textContent` contains it, case- and diacritic-insensitively.
    ///    Image items never match a query. A `#…` query is tag-autocomplete
    ///    mode and does not narrow the list at all.
    /// 3. Pinned items float to the top.
    ///
    /// The pinned-first step is a **stable partition**: pinned items keep their
    /// relative order and so do the rest. (The original used
    /// `sorted { $0.isPinned && !$1.isPinned }`, which is not a strict weak
    /// ordering and let `sort` shuffle equal elements arbitrarily.)
    static func apply(_ items: [ClipboardItem], _ f: FilterState) -> [ClipboardItem] {
        var base = items
        if let tag = f.tag {
            base = base.filter { $0.tags.contains(tag) }
        }
        let query = f.query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty && !query.hasPrefix("#") {
            base = base.filter { item in
                guard item.type == .text else { return false }
                return item.textContent?.localizedCaseInsensitiveContains(query) ?? false
            }
        }
        var pinned: [ClipboardItem] = []
        var rest: [ClipboardItem] = []
        pinned.reserveCapacity(base.count)
        rest.reserveCapacity(base.count)
        for item in base {
            if item.isPinned { pinned.append(item) } else { rest.append(item) }
        }
        return pinned + rest
    }
}
