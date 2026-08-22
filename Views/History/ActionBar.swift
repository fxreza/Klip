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

    var body: some View {
        HStack(spacing: 12) {
            toggles

            Divider()
                .frame(height: 14)

            legend
                .frame(maxWidth: .infinity, alignment: .leading)
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
    // `ViewThatFits` picks the first tier whose items all fit in the space
    // left by the toggles and divider, so the row never wraps — lower-priority
    // items (window toggles, then tag/copy, then item actions) are the ones
    // that disappear first as the window narrows. With the Paste button gone
    // (3.0.1) the full tier fits at the default window width.

    @ViewBuilder
    private var legend: some View {
        if viewModel.isEditing {
            editingLegend
        } else {
            ViewThatFits(in: .horizontal) {
                legendRow(fullLegendItems)
                legendRow(reducedLegendItems)
                legendRow(minimalLegendItems)
            }
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

    /// Everything: navigation, paste, every item action and both window
    /// toggles.
    private var fullLegendItems: [(key: String, label: String)] {
        var items = baseLegendItems
        items.append((shortcuts.displayString(for: .addTag), "tag"))
        items.append((shortcuts.displayString(for: .copy), "copy"))
        items.append((shortcuts.displayString(for: .toggleSidebar), "sidebar"))
        items.append((shortcuts.displayString(for: .togglePreview), "preview"))
        return items
    }

    /// Drops the window toggles and the less-used copy/tag shortcuts, keeps
    /// paste and the item actions.
    private var reducedLegendItems: [(key: String, label: String)] {
        baseLegendItems
    }

    /// Guaranteed to fit almost anywhere: navigate + paste only.
    private var minimalLegendItems: [(key: String, label: String)] {
        [
            ("↑↓", "navigate"),
            (shortcuts.displayString(for: .paste), "paste"),
        ]
    }

    /// Shared by the full and reduced tiers: navigate, multi-select, paste,
    /// paste plain, pin, favorite, lock, and the two contextual item actions
    /// (edit / save image).
    ///
    /// `paste plain` (⌥↩) sits right next to `paste` (↩) — with the Paste
    /// button and its split menu gone, the legend is the only place the
    /// plain-text alternate is discoverable outside the row context menu.
    private var baseLegendItems: [(key: String, label: String)] {
        var items: [(key: String, label: String)] = [
            ("↑↓", "navigate"),
            ("⇧↑↓", "multi-select"),
            (shortcuts.displayString(for: .paste), "paste"),
            (shortcuts.displayString(for: .pastePlain), "paste plain"),
            (shortcuts.displayString(for: .pin), "pin"),
            (shortcuts.displayString(for: .star), "favorite"),
            (shortcuts.displayString(for: .lock), "lock"),
        ]
        if let item = viewModel.selectedItem, item.isEditable {
            items.append((shortcuts.displayString(for: .edit), "edit"))
        }
        if viewModel.selectedItem?.type == .image {
            items.append((shortcuts.displayString(for: .saveToDisk), "save to disk"))
        }
        return items
    }

    private func legendRow(_ items: [(key: String, label: String)]) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                legendItem(item.key, item.label)
            }
        }
        .lineLimit(1)
    }

    private func legendItem(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
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
    }
}
