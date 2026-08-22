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
    ]

    // MARK: - Fixtures

    private static func text(_ content: String, pinned: Bool = false, tags: [String] = []) -> ClipboardItem {
        ClipboardItem(type: .text, textContent: content, isPinned: pinned, tags: tags)
    }

    private static func image(pinned: Bool = false, tags: [String] = []) -> ClipboardItem {
        ClipboardItem(type: .image, imageFilename: "images/\(UUID().uuidString).png", isPinned: pinned, tags: tags)
    }

    private static func contents(_ items: [ClipboardItem]) -> [String] {
        items.map { $0.textContent ?? "<image>" }
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
}
