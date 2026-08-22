import AppKit
import Foundation

// Task 6B follow-up — the shortcut legend's up-to-two-row wrap.
// `LegendRowPacking` (Views/History/ActionBar.swift) is a plain, View-free
// function specifically so this decision — "does the full legend fit in two
// rows at this width, or should ActionBar fall back to the reduced tier" —
// is unit testable without instantiating SwiftUI.

enum ActionBarLegendTests {
    static let tests: [(String, () throws -> Void)] = [
        ("packRows_emptyEntries_returnsNoRows", testEmpty),
        ("packRows_allEntriesFitOneRow_singleRow", testSingleRow),
        ("packRows_notEnoughRoomForThirdEntry_wrapsItToTheNextRow", testWrapsAfterBudget),
        ("packRows_maxWidthZero_putsEveryEntryOnItsOwnRow", testZeroWidth),
        ("packRows_oneEntryWiderThanMaxWidth_stillGetsItsOwnRowNotDropped", testOversizedEntry),
        ("packRows_manyNarrowEntries_canExceedTwoRows_soCallerMustFallBack", testExceedsTwoRows),
        ("itemWidth_includesKeyBadgePaddingAndTheKeyLabelGap", testItemWidthIncludesChrome),
    ]

    static let fontSize: CGFloat = 10

    static func testEmpty() throws {
        try expectEqual(LegendRowPacking.packRows([], fontSize: fontSize, maxWidth: 400).count, 0, "no entries means no rows")
    }

    /// Enough width for every entry (plus inter-item spacing) keeps them on
    /// one row, exactly like the pre-wrap single-row tiers used to render.
    static func testSingleRow() throws {
        let entries = [
            LegendEntry(key: "↑↓", label: "navigate"),
            LegendEntry(key: "⇧↑↓", label: "multi-select"),
            LegendEntry(key: "↩", label: "paste"),
        ]
        let total = entries.reduce(CGFloat(0)) { $0 + LegendRowPacking.itemWidth($1, fontSize: fontSize) }
            + LegendRowPacking.itemSpacing * CGFloat(entries.count - 1)

        let rows = LegendRowPacking.packRows(entries, fontSize: fontSize, maxWidth: total + 1)

        try expectEqual(rows.count, 1, "everything fits comfortably on one row")
        try expectEqual(rows.first?.count, 3)
    }

    /// A width budget that fits exactly the first two entries wraps the
    /// third onto row two rather than truncating or overflowing row one.
    static func testWrapsAfterBudget() throws {
        let a = LegendEntry(key: "↑↓", label: "navigate")
        let b = LegendEntry(key: "⇧↑↓", label: "multi-select")
        let c = LegendEntry(key: "↩", label: "paste")
        let widthA = LegendRowPacking.itemWidth(a, fontSize: fontSize)
        let widthB = LegendRowPacking.itemWidth(b, fontSize: fontSize)
        let maxWidth = widthA + LegendRowPacking.itemSpacing + widthB + 1

        let rows = LegendRowPacking.packRows([a, b, c], fontSize: fontSize, maxWidth: maxWidth)

        try expectEqual(rows.count, 2, "c does not fit alongside a and b, so it wraps to its own row")
        try expectEqual(rows[0].map { $0.label }, ["navigate", "multi-select"])
        try expectEqual(rows[1].map { $0.label }, ["paste"])
    }

    static func testZeroWidth() throws {
        let entries = [LegendEntry(key: "↑↓", label: "navigate"), LegendEntry(key: "↩", label: "paste")]

        let rows = LegendRowPacking.packRows(entries, fontSize: fontSize, maxWidth: 0)

        try expectEqual(rows.count, 2, "nothing fits within zero width, so every entry gets its own row")
    }

    /// An entry wider than the whole budget must not be silently dropped or
    /// split — it still gets a row of its own, same as the file-preview
    /// pane never truncates a name it can't fully show.
    static func testOversizedEntry() throws {
        let huge = LegendEntry(key: "⌘⇧⌥⌃X", label: "a very long label that will not fit")
        let small = LegendEntry(key: "↩", label: "paste")
        let hugeWidth = LegendRowPacking.itemWidth(huge, fontSize: fontSize)

        let rows = LegendRowPacking.packRows([huge, small], fontSize: fontSize, maxWidth: hugeWidth - 20)

        try expectEqual(rows.count, 2, "the oversized entry still gets its own row")
        try expectEqual(rows[0].map { $0.label }, ["a very long label that will not fit"])
        try expectEqual(rows[1].map { $0.label }, ["paste"])
    }

    /// `packRows` itself has no idea what `maxRows` means — it just keeps
    /// wrapping. `ActionBar.legend` is the one that checks
    /// `rows.count <= LegendRowPacking.maxRows` and falls back to the reduced
    /// tier when it doesn't hold, which this asserts is possible to trigger.
    static func testExceedsTwoRows() throws {
        let entries = (0..<6).map { LegendEntry(key: "⌘\($0)", label: "action \($0)") }
        let oneEntryWidth = LegendRowPacking.itemWidth(entries[0], fontSize: fontSize)

        let rows = LegendRowPacking.packRows(entries, fontSize: fontSize, maxWidth: oneEntryWidth + 1)

        try expect(rows.count > LegendRowPacking.maxRows, "a tight-enough budget produces more rows than the cap")
    }

    /// The measured width is more than the raw key + label text — it must
    /// include the key badge's padding and the key/label gap `legendItem`
    /// actually renders, or the wrap decision would run too optimistic and
    /// clip a row.
    static func testItemWidthIncludesChrome() throws {
        let entry = LegendEntry(key: "↩", label: "paste")
        let font = NSFont.systemFont(ofSize: fontSize)
        let rawKeyWidth = ("↩" as NSString).size(withAttributes: [.font: font]).width
        let rawLabelWidth = ("paste" as NSString).size(withAttributes: [.font: font]).width

        let measured = LegendRowPacking.itemWidth(entry, fontSize: fontSize)

        try expect(
            measured > rawKeyWidth + rawLabelWidth,
            "the measurement adds the key badge's padding and the key/label gap, not just raw text widths"
        )
    }
}
