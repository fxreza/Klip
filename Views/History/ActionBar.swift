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
struct ActionBar: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var settings: SettingsManager
    @ObservedObject private var shortcuts = ShortcutManager.shared

    /// Width available to `legend` — the HStack's leftover space after the
    /// toggles and divider — measured by the `GeometryReader` in
    /// `.background` below. Read by `legend` to decide the full tier's
    /// row-wrap (task 6B follow-up).
    ///
    /// Starts at 0 so the very first layout pass, before a real measurement
    /// lands, conservatively falls back to the reduced/minimal
    /// `ViewThatFits` rather than risking an overflowing full-tier row for
    /// one frame.
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
            .help(settings.sidebarCollapsed ? "Show sidebar" : "Hide sidebar")

            Button {
                withAnimation(Theme.selectionSpring) { viewModel.togglePreviewPane() }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(Theme.icon(13))
                    .foregroundStyle(settings.showPreviewPane ? Theme.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(settings.showPreviewPane ? "Hide preview" : "Show preview")
        }
    }

    // MARK: - Middle: shortcut legend
    //
    // The full tier (every shortcut) now wraps onto up to two compact rows
    // instead of dropping straight to the reduced tier the moment it no
    // longer fits on one line (task 6B follow-up: "⌥↩ paste plain" and
    // "# tags" were disappearing at the true default window width, sidebar +
    // preview both docked, ~380pt left for the legend). `LegendRowPacking`
    // measures each entry's real rendered width (same font, same padding as
    // `legendItem`) and greedily wraps the full tier at `legendAvailableWidth`
    // — only when that still needs more than two rows does the legend fall
    // back to the reduced/minimal `ViewThatFits`, same as before.

    @ViewBuilder
    private var legend: some View {
        if viewModel.isEditing {
            editingLegend
        } else {
            let rows = LegendRowPacking.packRows(
                fullLegendItems,
                fontSize: legendFontSize,
                maxWidth: legendAvailableWidth
            )
            if rows.count <= LegendRowPacking.maxRows {
                VStack(alignment: .leading, spacing: LegendRowPacking.rowSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        legendRow(row)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    legendRow(reducedLegendItems)
                    legendRow(minimalLegendItems)
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

    /// Everything: navigation, paste, every item action and both window
    /// toggles.
    private var fullLegendItems: [LegendEntry] {
        var items = baseLegendItems
        items.append(LegendEntry(key: shortcuts.displayString(for: .addTag), label: "tag"))
        items.append(LegendEntry(key: shortcuts.displayString(for: .copy), label: "copy"))
        items.append(LegendEntry(key: shortcuts.displayString(for: .toggleSidebar), label: "sidebar"))
        items.append(LegendEntry(key: shortcuts.displayString(for: .togglePreview), label: "preview"))
        return items
    }

    /// Drops the window toggles and the less-used copy/tag shortcuts, keeps
    /// paste and the item actions. Used only when the full tier doesn't fit
    /// even wrapped onto two rows.
    private var reducedLegendItems: [LegendEntry] {
        baseLegendItems
    }

    /// Guaranteed to fit almost anywhere: navigate + paste only.
    private var minimalLegendItems: [LegendEntry] {
        [
            LegendEntry(key: "↑↓", label: "navigate"),
            LegendEntry(key: shortcuts.displayString(for: .paste), label: "paste"),
        ]
    }

    /// Shared by the full and reduced tiers: navigate, multi-select, paste,
    /// paste plain, `#tag` search, pin, favorite, lock, and the two
    /// contextual item actions (edit / save image).
    ///
    /// `paste plain` (⌥↩) sits right next to `paste` (↩) — with the Paste
    /// button and its split menu gone, the legend is the only place the
    /// plain-text alternate is discoverable outside the row context menu.
    /// `# tags` (task 6B) sits right after it: neither the `#tag` search
    /// syntax nor the Tags chip is otherwise hinted anywhere in the window.
    private var baseLegendItems: [LegendEntry] {
        var items: [LegendEntry] = [
            LegendEntry(key: "↑↓", label: "navigate"),
            LegendEntry(key: "⇧↑↓", label: "multi-select"),
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
        if viewModel.selectedItem?.type == .image {
            items.append(LegendEntry(key: shortcuts.displayString(for: .saveToDisk), label: "save to disk"))
        }
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
            row.help(help)
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
/// decision — "does the full tier fit in two rows at this width, or should
/// `ActionBar` fall back to the reduced tier" — is a plain function `Tests/`
/// can call directly, instead of depending on `ViewThatFits`'s internal
/// fit-detection (which measures a candidate's *ideal*, unconstrained size,
/// not "wrapped to fit width W" — no combination of `ViewThatFits` and a
/// custom wrapping `Layout` can express "wrap within the available width,
/// but only if that takes two rows or fewer").
enum LegendRowPacking {
    static let itemSpacing: CGFloat = 10
    static let rowSpacing: CGFloat = 4
    static let maxRows = 2

    /// Conservative per-item safety margin over the raw text measurement,
    /// covering rounding/kerning differences between `NSAttributedString`
    /// sizing (used here, so this stays a plain function) and SwiftUI's own
    /// `Text` layout — better to wrap, or fall back to the reduced tier, a
    /// little early than to clip a row.
    private static let perItemSafetyMargin: CGFloat = 4

    /// `entry`'s rendered width: its key badge (text + 4pt padding each
    /// side) plus the 4pt gap to the label plus the label — mirrors
    /// `ActionBar.legendItem` exactly so the measurement matches what is
    /// actually drawn.
    static func itemWidth(_ entry: LegendEntry, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let keyWidth = (entry.key as NSString).size(withAttributes: attrs).width
        let labelWidth = (entry.label as NSString).size(withAttributes: attrs).width
        return keyWidth + 8 + 4 + labelWidth + perItemSafetyMargin
    }

    /// Greedily wraps `entries` into rows no wider than `maxWidth`, in order,
    /// never splitting a single entry across rows — one wider than
    /// `maxWidth` on its own still gets a row to itself rather than being
    /// dropped or clipped mid-entry.
    static func packRows(_ entries: [LegendEntry], fontSize: CGFloat, maxWidth: CGFloat) -> [[LegendEntry]] {
        guard !entries.isEmpty else { return [] }
        var rows: [[LegendEntry]] = [[]]
        var rowWidth: CGFloat = 0
        for entry in entries {
            let width = itemWidth(entry, fontSize: fontSize)
            let needed = rowWidth == 0 ? width : rowWidth + itemSpacing + width
            if needed > maxWidth, !rows[rows.count - 1].isEmpty {
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
