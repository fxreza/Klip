import Foundation

/// Which sidebar section the list is showing.
///
/// `Hashable` so it can key `matchedGeometryEffect` comparisons and sidebar
/// row identity.
enum Scope: Hashable {
    case all
    case favorites
    case folder(UUID)
}

/// The content-kind filter chosen in the chip row under the search field.
///
/// `.all` is the neutral state. The chips deliberately do not offer
/// `ContentKind.richText`: rich-text capture is Phase 3D, and until then a
/// rich-text clip reads as plain text to the user, so it lives under the
/// **Text** chip (see `FilterState.matches`).
enum ChipFilter: Hashable {
    case all
    case kind(ContentKind)

    /// The chips shown, in bar order.
    static let bar: [ChipFilter] = [
        .all,
        .kind(.text),
        .kind(.link),
        .kind(.image),
        .kind(.file),
        .kind(.color),
        .kind(.code),
        .kind(.email),
        .kind(.phone),
    ]

    var label: String {
        switch self {
        case .all: return "All"
        case .kind(let kind): return kind.label
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .kind(let kind): return kind.systemImage
        }
    }
}

/// The inputs that decide which clipboard items the history list shows.
///
/// Kept as a plain value type with a pure `apply` so the filtering rules can be
/// unit-tested without a store, a window or SwiftUI (see `Tests/FilterStateTests.swift`).
struct FilterState: Equatable {
    /// Raw search field text (already debounced by the view model).
    var query: String
    /// Active tag chip filter, or nil.
    var tag: String?
    /// Sidebar section.
    var scope: Scope
    /// Content-kind chip.
    var chip: ChipFilter

    init(query: String = "", tag: String? = nil, scope: Scope = .all, chip: ChipFilter = .all) {
        self.query = query
        self.tag = tag
        self.scope = scope
        self.chip = chip
    }

    /// Does `item` belong to `scope`?
    ///
    /// Per decision D4, filing a clip into a folder does **not** remove it from
    /// "All" — the history stays a complete timeline.
    static func matches(_ item: ClipboardItem, scope: Scope) -> Bool {
        switch scope {
        case .all:            return true
        case .favorites:      return item.isBookmarked
        case .folder(let id): return item.folderID == id
        }
    }

    /// Does `item` belong under `chip`?
    ///
    /// `kind` is `nil` for every item captured before Phase 3C's detector
    /// existed, so the rules are written to be correct for un-detected items:
    /// - `.all` matches everything.
    /// - **Image** and **File** key off the storage `type`, which is always set.
    /// - **Text** is the catch-all for text items that have not been classified
    ///   as something more specific (`kind == nil`) plus explicit
    ///   `.text` / `.richText`.
    /// - Every other chip requires an exact `kind` match, so it shows nothing
    ///   until detection backfills.
    static func matches(_ item: ClipboardItem, chip: ChipFilter) -> Bool {
        switch chip {
        case .all:
            return true
        case .kind(.image):
            return item.type == .image
        case .kind(.file):
            return item.isFile
        case .kind(.text):
            return item.type == .text && (item.kind == nil || item.kind == .text || item.kind == .richText)
        case .kind(let kind):
            return item.kind == kind
        }
    }

    /// Case- and diacritic-folded search blob for one item, built once per
    /// filter pass (never per query word). Pulls in every field the query is
    /// allowed to match: `textContent` (the 500-char preview for large,
    /// file-backed text — never the full file, per `ClipboardStore.fullText`'s
    /// doc comment: filtering must not read files), `ocrText`, tag names,
    /// `sourceApp`, and file names (`fileAttachment.originalName` plus
    /// `additionalNames`). Link/email/phone/code items already store their
    /// text in `textContent`, so they need no extra field.
    ///
    /// An image with no OCR text contributes only its (possibly empty) tags
    /// and source app here, matching the old all-or-nothing behaviour for the
    /// common case: no tag, no matching source app, no match.
    private static func searchBlob(for item: ClipboardItem) -> String {
        var parts: [String] = []
        if let text = item.textContent { parts.append(text) }
        if let ocr = item.ocrText { parts.append(ocr) }
        if !item.tags.isEmpty { parts.append(item.tags.joined(separator: " ")) }
        if let sourceApp = item.sourceApp { parts.append(sourceApp) }
        if let attachment = item.fileAttachment {
            parts.append(attachment.originalName)
            if !attachment.additionalNames.isEmpty {
                parts.append(attachment.additionalNames.joined(separator: " "))
            }
        }
        return parts.joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// Filter + order `items` for display.
    ///
    /// Rules:
    /// 1. Scope (sidebar section) narrows first.
    /// 2. If a tag filter is active, keep only items carrying that tag.
    /// 3. The content-kind chip narrows next (see `matches(_:chip:)`).
    /// 4. A non-empty query that does not start with `#` matches items whose
    ///    text content, OCR text, tag names, source app, or file name(s)
    ///    contain every word of the query, case- and diacritic-insensitively
    ///    (see `searchBlob(for:)`). Multi-word queries are AND'd across all of
    ///    those fields combined, not per-field. An image with none of those
    ///    fields set (no OCR text, no tags, no matching source app) still
    ///    matches nothing, as before. A `#…` query is tag-autocomplete mode
    ///    and does not narrow the list at all.
    /// 5. Pinned items float to the top.
    ///
    /// The pinned-first step is a **stable partition**: pinned items keep their
    /// relative order and so do the rest. (The original used
    /// `sorted { $0.isPinned && !$1.isPinned }`, which is not a strict weak
    /// ordering and let `sort` shuffle equal elements arbitrarily.)
    ///
    /// No relevance ranking is applied anywhere here, intentionally: the list
    /// stays in chronological (pinned-first) order no matter which fields a
    /// query happened to match, so the user's muscle memory for row position
    /// keeps working.
    static func apply(_ items: [ClipboardItem], _ f: FilterState) -> [ClipboardItem] {
        var base = items
        if f.scope != .all {
            base = base.filter { matches($0, scope: f.scope) }
        }
        if let tag = f.tag {
            base = base.filter { $0.tags.contains(tag) }
        }
        if f.chip != .all {
            base = base.filter { matches($0, chip: f.chip) }
        }
        let query = f.query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty && !query.hasPrefix("#") {
            let words = query
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .split(separator: " ")
                .map(String.init)
            base = base.filter { item in
                let blob = searchBlob(for: item)
                return words.allSatisfy { blob.contains($0) }
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
