import AppKit
import SwiftUI

/// Bottom bar: layout toggles on the left, the shortcut legend filling the
/// rest.
///
/// 3.0.1 removed the blue Paste button (and its split menu). ↩ / ⌥↩ are the
/// paste affordances now — both are in the legend — and the "Always paste as
/// plain text" toggle lives in Settings > General, where the split menu's copy
/// of it always pointed anyway.
///
/// The legend is built from `ShortcutManager.shared.displayString(for:)`, so
/// rebinding a key in Settings > Shortcuts updates it immediately — the
/// `@ObservedObject var shortcuts` subscription below is what makes that
/// live rather than a one-time read.
///
/// There used to be three tiers (full / reduced / minimal) picked with
/// `ViewThatFits`, and the moment the full tier needed more than two rows the
/// legend cut straight to a two-entry minimal tier — nearly every shortcut
/// vanishing at once, leaving a wide empty gap. That cliff is gone: there is
/// now a single priority-ordered entry list that `LegendRowPacking` packs
/// into at most two rows and *truncates* rather than tier-collapses, so a
/// narrower window drops one entry at a time from the low-priority end
/// instead of jumping to almost nothing. See the comment above `legend`.
struct ActionBar: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var settings: SettingsManager
    @ObservedObject private var shortcuts = ShortcutManager.shared

    /// Width available to `legend` — the HStack's leftover space after the
    /// toggles and divider — measured by the `GeometryReader` in
    /// `.background` below. Read by `legend` to decide how many entries fit
    /// in the up-to-two-row wrap (task 6B follow-up).
    ///
    /// Starts at 0 so the very first layout pass, before a real measurement
    /// lands, conservatively truncates down to nothing rather than risking
    /// an overflowing row for one frame.
    @State private var legendAvailableWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            toggles

            Divider()
                .frame(height: 14)

            legend
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { legendAvailableWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { legendAvailableWidth = $0 }
                    }
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.barBackground)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Theme.separator),
            alignment: .top
        )
    }

    // MARK: - Left: layout toggles

    private var toggles: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(Theme.selectionSpring) { viewModel.toggleSidebar() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(Theme.icon(13))
                    .foregroundStyle(settings.sidebarCollapsed ? Color.secondary : Theme.accent)
            }
            .buttonStyle(.plain)
            .klipHelp(settings.sidebarCollapsed ? "Show sidebar" : "Hide sidebar")

            Button {
                withAnimation(Theme.selectionSpring) { viewModel.togglePreviewPane() }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(Theme.icon(13))
                    .foregroundStyle(settings.showPreviewPane ? Theme.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .klipHelp(settings.showPreviewPane ? "Hide preview" : "Show preview")
        }
    }

    // MARK: - Middle: shortcut legend
    //
    // One priority-ordered entry list (`legendItems`), wrapped onto up to two
    // compact rows at `legendAvailableWidth` (task 6B follow-up: "⌥↩ paste
    // plain" and "# tags" were disappearing at the true default window
    // width, sidebar + preview both docked, ~380pt left for the legend).
    //
    // This used to fall back to a wholly different "reduced/minimal" entry
    // list — picked via `ViewThatFits` — the moment the full list needed more
    // than two rows. That was a cliff: `ViewThatFits` measures a candidate's
    // *ideal* unconstrained width, so the moment the reduced list (8-10
    // entries) couldn't fit on one line, `ViewThatFits` skipped straight to
    // the two-entry minimal list — nearly every shortcut disappearing at
    // once, leaving a big empty gap where `.frame(maxWidth: .infinity)` pads
    // out the row.
    //
    // `LegendRowPacking.packRows` now truncates instead of tier-collapsing:
    // it measures each entry's real rendered width (same font, same padding
    // as `legendItem`), greedily packs `legendItems` into at most two rows,
    // and silently drops whatever doesn't fit off the end. Because
    // `legendItems` is ordered most-important-first, a narrower window loses
    // one low-priority entry at a time instead of jumping to almost nothing,
    // and the legend always fills whatever space it actually has.

    @ViewBuilder
    private var legend: some View {
        if viewModel.isEditing {
            editingLegend
        } else if viewModel.isTrashScope {
            trashLegend
        } else {
            let rows = LegendRowPacking.packRows(
                legendItems,
                fontSize: legendFontSize,
                maxWidth: legendAvailableWidth
            )
            VStack(alignment: .leading, spacing: LegendRowPacking.rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    legendRow(row)
                }
            }
        }
    }

    /// The actual point size `.klip(.caption)` renders at right now — it
    /// scales with the user's "List text size" setting — so
    /// `LegendRowPacking`'s width measurement stays accurate at any scale.
    private var legendFontSize: CGFloat {
        KlipFontRole.caption.baseSize * settings.listFontScale
    }

    /// 5E. Short on purpose: in the trash there are exactly two things a key
    /// does, and both of them mean something different here than they do in
    /// the history, so spelling them out matters more than packing the row.
    private var trashLegend: some View {
        HStack(spacing: 10) {
            Text("Trash")
                .font(.klip(.caption))
                .fontWeight(.semibold)
                .foregroundStyle(Theme.accent)
            legendItem(
                shortcuts.displayString(for: .paste),
                "restore",
                help: "Put the selected clips back at the top of All"
            )
            legendItem(
                shortcuts.displayString(for: .delete),
                "delete forever",
                help: "Erase the selected clips, with a confirmation"
            )
            legendItem(shortcuts.displayString(for: .copy), "copy")
        }
    }

    private var editingLegend: some View {
        HStack(spacing: 10) {
            Text("Editing")
                .font(.klip(.caption))
                .fontWeight(.semibold)
                .foregroundStyle(Theme.accent)
            legendItem(shortcuts.displayString(for: .escape), "exit")
            legendItem(shortcuts.displayString(for: .edit), "save")
        }
    }

    /// Every legend entry, most important first. `packRows` packs these in
    /// order and drops whatever doesn't fit off the *end*, so this ordering
    /// is the whole truncation policy — whatever is listed last is the first
    /// thing to disappear in a narrow window.
    ///
    /// `navigate` (↑↓) and `multi-select` (⇧↑↓) are gone: navigation is
    /// self-evident, and multi-select is a power-user gesture that doesn't
    /// need a permanent legend slot. `sidebar` (⌥⌘S) and `preview` (⌥⌘P) are
    /// also gone: both toggles already have visible buttons at the
    /// bottom-left of this same bar, so the legend entries were a redundant
    /// second affordance for something already on screen.
    ///
    /// What's left, in priority order:
    /// - `paste` / `paste plain` — with the Paste button and its split menu
    ///   gone, the legend is the only place the plain-text alternate is
    ///   discoverable outside the row context menu, so both come first.
    /// - `# tags` (task 6B) — neither the `#tag` search syntax nor the Tags
    ///   chip is otherwise hinted anywhere in the window.
    /// - `pin` / `favorite` / `lock` — the three persistent per-item states,
    ///   in the order their buttons appear elsewhere in the UI.
    /// - `edit` / `save to disk` — contextual (editable text / image items
    ///   only), so they only ever cost space when they're actually relevant.
    /// - `tag` / `copy` — both have visible buttons elsewhere (the Tags chip,
    ///   the row's own copy affordance), so they're the least essential
    ///   legend entries and the first to go when space runs out.
    private var legendItems: [LegendEntry] {
        var items: [LegendEntry] = [
            LegendEntry(key: shortcuts.displayString(for: .paste), label: "paste"),
            LegendEntry(key: shortcuts.displayString(for: .pastePlain), label: "paste plain"),
            LegendEntry(key: "#", label: "tags", help: "Type #tag in search or use the Tags chip"),
            LegendEntry(key: shortcuts.displayString(for: .pin), label: "pin"),
            LegendEntry(key: shortcuts.displayString(for: .star), label: "favorite"),
            LegendEntry(key: shortcuts.displayString(for: .lock), label: "lock"),
        ]
        if let item = viewModel.selectedItem, item.isEditable {
            items.append(LegendEntry(key: shortcuts.displayString(for: .edit), label: "edit"))
        }
        if viewModel.selectedItem != nil {
            items.append(LegendEntry(
                key: shortcuts.displayString(for: .renameClip),
                label: "name",
                help: "Give the clip a name, shown in place of its first line"
            ))
        }
        if viewModel.selectedItem != nil {
            items.append(LegendEntry(
                key: shortcuts.displayString(for: .quickLook),
                label: "preview",
                help: "Quick Look the clip. Space works when the search field is empty; ⌘Y always works"
            ))
        }
        if viewModel.selectedItem?.type == .image {
            items.append(LegendEntry(key: shortcuts.displayString(for: .saveToDisk), label: "save to disk"))
        }
        items.append(LegendEntry(key: shortcuts.displayString(for: .addTag), label: "tag"))
        items.append(LegendEntry(key: shortcuts.displayString(for: .copy), label: "copy"))
        return items
    }

    private func legendRow(_ items: [LegendEntry]) -> some View {
        HStack(spacing: LegendRowPacking.itemSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                legendItem(item.key, item.label, help: item.help)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func legendItem(_ key: String, _ label: String, help: String? = nil) -> some View {
        let row = HStack(spacing: 4) {
            Text(key)
                .font(.klip(.caption))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.separator, lineWidth: 0.5)
                )
            Text(label)
                .font(.klip(.caption))
                .foregroundStyle(.secondary)
        }
        .fixedSize()

        if let help {
            row.klipHelp(help)
        } else {
            row
        }
    }
}

/// One shortcut-legend entry. `help` is an optional tooltip for entries whose
/// key glyph alone doesn't say enough (task 6B's `# tags`).
///
/// Not private/nested so `LegendRowPacking`'s wrap decision — and
/// `Tests/ActionBarLegendTests.swift` — can use it without going through
/// `ActionBar` itself.
struct LegendEntry: Equatable {
    let key: String
    let label: String
    var help: String? = nil
}

/// Pure width-measurement + row-packing for the legend's up-to-two-row wrap
/// (task 6B follow-up). Deliberately free of `View`/`Layout` so the packing
/// decision — "how many of these entries fit in two rows at this width, and
/// which ones get dropped" — is a plain function `Tests/` can call directly,
/// instead of depending on `ViewThatFits`'s internal fit-detection (which
/// measures a candidate's *ideal*, unconstrained size, not "wrapped to fit
/// width W" — no combination of `ViewThatFits` and a custom wrapping
/// `Layout` can express "wrap within the available width, and once you run
/// out of rows just drop whatever's left").
enum LegendRowPacking {
    static let itemSpacing: CGFloat = 10
    static let rowSpacing: CGFloat = 4
    static let maxRows = 2


    /// `entry`'s rendered width: its key badge (text + 4pt padding each
    /// side) plus the 4pt gap to the label plus the label — mirrors
    /// `ActionBar.legendItem` exactly so the measurement matches what is
    /// actually drawn.
    static func itemWidth(_ entry: LegendEntry, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let keyWidth = (entry.key as NSString).size(withAttributes: attrs).width
        let labelWidth = (entry.label as NSString).size(withAttributes: attrs).width
        // Rounded up, with no extra padding on top.
        //
        // There used to be a flat 4pt "safety margin" added to every item, to
        // absorb rounding differences between `NSAttributedString` sizing
        // (used here, so this stays a plain testable function) and SwiftUI's
        // `Text` layout. It scaled the waste with the number of shortcuts on
        // screen: at nine visible entries it left 36pt — about six characters
        // — of dead space at the right-hand end, while shrinking the window by
        // a single pixel still bumped the last entry onto the next row.
        //
        // The difference it guarded against is sub-pixel. SwiftUI lays `Text`
        // out on whole points, so rounding up models that exactly and is
        // already conservative by up to a point per item; `itemSpacing` is
        // exact. Nothing further is needed, and anything further is visible as
        // a gap.
        return (keyWidth + 8 + 4 + labelWidth).rounded(.up)
    }

    /// Greedily wraps `entries` into at most `maxRows` rows no wider than
    /// `maxWidth`, in order, never splitting a single entry across rows — one
    /// wider than `maxWidth` on its own still gets a row to itself rather
    /// than being dropped or clipped mid-entry.
    ///
    /// This is graceful truncation, not tier-collapse: once `maxRows` rows
    /// are full and the next entry doesn't fit on the last one, packing
    /// simply stops — that entry and everything after it in `entries` (the
    /// lowest-priority tail, by convention of the caller's ordering) is
    /// dropped, rather than the caller falling back to some wholly different,
    /// much-shorter entry list. The legend degrades one entry at a time and
    /// always fills the space it has, instead of jumping from "almost
    /// everything" to "almost nothing" the moment it doesn't fit.
    static func packRows(
        _ entries: [LegendEntry],
        fontSize: CGFloat,
        maxWidth: CGFloat,
        maxRows: Int = Self.maxRows
    ) -> [[LegendEntry]] {
        guard !entries.isEmpty, maxRows > 0 else { return [] }
        var rows: [[LegendEntry]] = [[]]
        var rowWidth: CGFloat = 0
        for entry in entries {
            let width = itemWidth(entry, fontSize: fontSize)
            let needed = rowWidth == 0 ? width : rowWidth + itemSpacing + width
            if needed > maxWidth, !rows[rows.count - 1].isEmpty {
                // The current row is full and this entry doesn't fit on it.
                // If we've already used every row we're allowed, there's
                // nowhere left to put it — stop packing and drop this entry
                // and the rest of the tail, rather than starting a row
                // `ActionBar` would never render.
                guard rows.count < maxRows else { break }
                rows.append([entry])
                rowWidth = width
            } else {
                rows[rows.count - 1].append(entry)
                rowWidth = needed
            }
        }
        return rows
    }
}
