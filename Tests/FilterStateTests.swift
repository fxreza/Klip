import Foundation

// Covers `Views/History/FilterState.swift` — the pure filter/order rules the
// history list uses. Extracted from HistoryContentView.computeFilteredItems in
// Phase 1A; the only intentional change is that the pinned-first step is now a
// stable partition instead of the invalid `sorted { $0.isPinned && !$1.isPinned }`.

enum FilterStateTests {
    static let tests: [(String, () throws -> Void)] = [
        ("emptyQuery_returnsAllItems_pinnedFirst_stableOrder", testEmptyQueryPinnedFirstStable),
        ("query_matchesTextItemsOnly_caseInsensitive", testQueryMatchesTextOnly),
        ("hashQuery_isTagMode_andDoesNotNarrowTheList", testHashQueryIsTagMode),
        ("tagFilter_keepsOnlyItemsCarryingTheTag", testTagFilter),
        ("tagFilterAndQuery_combine", testMixed),
        ("emptyAndWhitespaceQuery_areTreatedAsNoQuery", testWhitespaceQuery),
        ("scope_all_keepsEverythingIncludingFoldered", testScopeAll),
        ("scope_favorites_keepsBookmarkedOnly", testScopeFavorites),
        ("scope_folder_keepsThatFolderOnly", testScopeFolder),
        ("chip_all_isANoOp", testChipAll),
        ("chip_image_matchesImageTypeRegardlessOfKind", testChipImage),
        ("chip_file_matchesItemsWithAnAttachment", testChipFile),
        ("chip_text_isTheCatchAllForUndetectedText", testChipText),
        ("chip_specificKinds_requireAnExactKindMatch", testChipSpecificKinds),
        ("scopeChipTagAndQuery_combine", testScopeChipCombine),
    ]

    // MARK: - Fixtures

    private static func text(
        _ content: String,
        pinned: Bool = false,
        tags: [String] = [],
        bookmarked: Bool = false,
        folder: UUID? = nil,
        kind: ContentKind? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            textContent: content,
            isPinned: pinned,
            isBookmarked: bookmarked,
            tags: tags,
            folderID: folder,
            kind: kind
        )
    }

    private static func image(
        pinned: Bool = false,
        tags: [String] = [],
        bookmarked: Bool = false,
        folder: UUID? = nil,
        kind: ContentKind? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            type: .image,
            imageFilename: "images/\(UUID().uuidString).png",
            isPinned: pinned,
            isBookmarked: bookmarked,
            tags: tags,
            folderID: folder,
            kind: kind
        )
    }

    private static func file(_ name: String, bookmarked: Bool = false, folder: UUID? = nil) -> ClipboardItem {
        var item = ClipboardItem.file(attachment: FileAttachment(originalName: name, byteSize: 10))
        item.isBookmarked = bookmarked
        item.folderID = folder
        return item
    }

    private static func contents(_ items: [ClipboardItem]) -> [String] {
        items.map { item in
            if let attachment = item.fileAttachment { return attachment.originalName }
            return item.textContent ?? "<image>"
        }
    }

    // MARK: - Tests

    /// An empty query returns every item, pinned ones hoisted to the front, and
    /// both groups keep the order they had in the input.
    static func testEmptyQueryPinnedFirstStable() throws {
        let items = [
            text("a"),
            text("b", pinned: true),
            text("c"),
            text("d", pinned: true),
            text("e"),
        ]

        let result = FilterState.apply(items, FilterState())

        try expectEqual(result.count, items.count, "empty query should keep every item")
        try expectEqual(contents(result), ["b", "d", "a", "c", "e"], "pinned items first, each group in original order")
    }

    /// Images never match a text query, and matching is case-insensitive.
    static func testQueryMatchesTextOnly() throws {
        let items = [
            text("Hello World"),
            image(),
            text("goodbye"),
            text("say hello again"),
        ]

        let result = FilterState.apply(items, FilterState(query: "HELLO"))

        try expectEqual(contents(result), ["Hello World", "say hello again"], "only text items whose content contains the query, case-insensitively")

        let noMatch = FilterState.apply(items, FilterState(query: "zzz"))
        try expectEqual(noMatch.count, 0, "a query matching nothing returns an empty list")
    }

    /// `#…` is tag-autocomplete mode: it must not narrow the list at all
    /// (the autocomplete bar handles it), but pinned-first still applies.
    static func testHashQueryIsTagMode() throws {
        let items = [
            text("alpha", tags: ["work"]),
            text("beta", pinned: true),
            image(tags: ["work"]),
        ]

        let result = FilterState.apply(items, FilterState(query: "#wo"))

        try expectEqual(result.count, 3, "a #query must not filter the list")
        try expectEqual(contents(result), ["beta", "alpha", "<image>"], "pinned-first still applies in tag mode")
    }

    /// The tag filter keeps only items carrying that exact tag — images included.
    static func testTagFilter() throws {
        let items = [
            text("alpha", tags: ["work"]),
            text("beta", tags: ["home"]),
            image(tags: ["work"]),
            text("gamma"),
            text("delta", pinned: true, tags: ["work"]),
        ]

        let result = FilterState.apply(items, FilterState(tag: "work"))

        try expectEqual(contents(result), ["delta", "alpha", "<image>"], "only #work items, pinned first, otherwise in order")

        let missing = FilterState.apply(items, FilterState(tag: "nope"))
        try expectEqual(missing.count, 0, "an unknown tag filters everything out")
    }

    /// Tag filter and text query are applied together (tag first, then query).
    static func testMixed() throws {
        let items = [
            text("apple pie", tags: ["food"]),
            text("apple watch", tags: ["tech"]),
            image(tags: ["food"]),
            text("banana bread", pinned: true, tags: ["food"]),
            text("apple crumble", pinned: true, tags: ["food"]),
        ]

        let result = FilterState.apply(items, FilterState(query: "apple", tag: "food"))

        try expectEqual(contents(result), ["apple crumble", "apple pie"], "tag then query, pinned first, images dropped by the query")
    }

    /// A whitespace-only query behaves like no query at all.
    static func testWhitespaceQuery() throws {
        let items = [text("alpha"), image(), text("beta", pinned: true)]

        let blank = FilterState.apply(items, FilterState(query: "   "))
        try expectEqual(blank.count, 3, "a whitespace-only query should not filter anything")
        try expectEqual(contents(blank), ["beta", "alpha", "<image>"], "pinned-first order for a blank query")

        // Surrounding whitespace is trimmed before matching.
        let padded = FilterState.apply(items, FilterState(query: "  alpha  "))
        try expectEqual(contents(padded), ["alpha"], "query should be trimmed before matching")
    }

    // MARK: - Scope (sidebar sections)

    /// Per decision D4, a clip filed into a folder stays visible in "All".
    static func testScopeAll() throws {
        let folderID = UUID()
        let items = [
            text("loose"),
            text("filed", folder: folderID),
            text("starred", bookmarked: true),
        ]

        let result = FilterState.apply(items, FilterState(scope: .all))
        try expectEqual(contents(result), ["loose", "filed", "starred"], "All shows everything, folders included")
    }

    /// Favorites is exactly the `isBookmarked` (star) flag, across every type.
    static func testScopeFavorites() throws {
        let items = [
            text("plain"),
            text("starred", bookmarked: true),
            image(bookmarked: true),
            text("pinned but not starred", pinned: true),
            file("Doc.pdf", bookmarked: true),
        ]

        let result = FilterState.apply(items, FilterState(scope: .favorites))
        try expectEqual(contents(result), ["starred", "<image>", "Doc.pdf"], "only bookmarked items, in list order")
    }

    /// A folder scope keeps exactly that folder's members.
    static func testScopeFolder() throws {
        let a = UUID()
        let b = UUID()
        let items = [
            text("in-a", folder: a),
            text("in-b", folder: b),
            text("loose"),
            text("pinned-in-a", pinned: true, folder: a),
        ]

        let result = FilterState.apply(items, FilterState(scope: .folder(a)))
        try expectEqual(contents(result), ["pinned-in-a", "in-a"], "only folder A, pinned first")

        let empty = FilterState.apply(items, FilterState(scope: .folder(UUID())))
        try expectEqual(empty.count, 0, "an unknown folder id filters everything out")
    }

    // MARK: - Content-kind chips

    static func testChipAll() throws {
        let items = [text("a"), image(), file("F.txt")]
        let result = FilterState.apply(items, FilterState(chip: .all))
        try expectEqual(result.count, 3, "the All chip must not filter anything")
    }

    /// Image keys off the storage type, so it works before detection backfills.
    static func testChipImage() throws {
        let items = [
            text("a"),
            image(),
            image(kind: .image),
            file("F.png"),
        ]
        let result = FilterState.apply(items, FilterState(chip: .kind(.image)))
        try expectEqual(result.count, 2, "both image items, detected or not; a .file item is not an image")
    }

    /// File keys off the attachment, so it works before detection backfills.
    static func testChipFile() throws {
        let items = [text("a"), image(), file("Report.pdf"), file("Sheet.xlsx")]
        let result = FilterState.apply(items, FilterState(chip: .kind(.file)))
        try expectEqual(contents(result), ["Report.pdf", "Sheet.xlsx"], "only items carrying a file attachment")
    }

    /// Text is the catch-all for text items that have no more specific kind.
    static func testChipText() throws {
        let items = [
            text("undetected"),                  // kind == nil → Text
            text("plain", kind: .text),
            text("styled", kind: .richText),     // richText has no chip → Text
            text("https://example.com", kind: .link),
            image(),
            file("F.txt"),
        ]
        let result = FilterState.apply(items, FilterState(chip: .kind(.text)))
        try expectEqual(
            contents(result),
            ["undetected", "plain", "styled"],
            "undetected text plus explicit text/richText; links, images and files excluded"
        )
    }

    /// Every other chip is an exact `kind` match, so it stays empty until
    /// Phase 3C's detector backfills `kind`.
    static func testChipSpecificKinds() throws {
        let items = [
            text("https://example.com"),                          // undetected
            text("https://example.org", kind: .link),
            text("me@example.com", kind: .email),
            text("#ff6600", kind: .color),
            text("let x = 1", kind: .code),
            text("+1 555 0100", kind: .phone),
        ]

        try expectEqual(contents(FilterState.apply(items, FilterState(chip: .kind(.link)))), ["https://example.org"], "Link")
        try expectEqual(contents(FilterState.apply(items, FilterState(chip: .kind(.email)))), ["me@example.com"], "Email")
        try expectEqual(contents(FilterState.apply(items, FilterState(chip: .kind(.color)))), ["#ff6600"], "Color")
        try expectEqual(contents(FilterState.apply(items, FilterState(chip: .kind(.code)))), ["let x = 1"], "Code")
        try expectEqual(contents(FilterState.apply(items, FilterState(chip: .kind(.phone)))), ["+1 555 0100"], "Phone")

        let undetectedOnly = [text("https://example.com")]
        try expectEqual(
            FilterState.apply(undetectedOnly, FilterState(chip: .kind(.link))).count,
            0,
            "an item with kind == nil never matches a specific-kind chip"
        )
    }

    /// Scope → tag → chip → query, all four at once.
    static func testScopeChipCombine() throws {
        let folderID = UUID()
        let items = [
            text("apple link", tags: ["work"], folder: folderID, kind: .link),
            text("apple link elsewhere", tags: ["work"], kind: .link),          // wrong scope
            text("apple link untagged", folder: folderID, kind: .link),         // wrong tag
            text("apple plain", tags: ["work"], folder: folderID, kind: .text), // wrong chip
            text("banana link", tags: ["work"], folder: folderID, kind: .link), // wrong query
        ]

        let result = FilterState.apply(
            items,
            FilterState(query: "apple", tag: "work", scope: .folder(folderID), chip: .kind(.link))
        )
        try expectEqual(contents(result), ["apple link"], "every predicate must hold")
    }
}
