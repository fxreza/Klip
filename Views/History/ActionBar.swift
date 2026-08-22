import SwiftUI

/// Bottom bar: layout toggles on the left, the shortcut legend in the middle,
/// the Paste button on the right.
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

            Spacer(minLength: 8)
                .frame(maxWidth: 8)

            // Unchanged: the button pastes the focused item (Enter is what
            // pastes a whole multi-selection). Phase 3D: mode comes from the
            // "Always paste as plain text" setting; the split button's menu
            // offers the explicit alternate.
            PasteButton(
                action: {
                    if let item = viewModel.selectedItem { viewModel.onPaste(item, viewModel.defaultPasteMode) }
                },
                pasteAlternate: {
                    if let item = viewModel.selectedItem { viewModel.onPaste(item, viewModel.alternatePasteMode) }
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
    // `ViewThatFits` picks the first tier whose items all fit in the space
    // left by the toggles/divider/Paste button, so the row never wraps and
    // never pushes the Paste button off a narrow window — lower-priority
    // items (window toggles, then tag/copy/plain-paste, then item actions)
    // are the ones that disappear first as the window narrows.

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

    /// Everything: navigation, every item action, both scope keys and both
    /// window toggles.
    private var fullLegendItems: [(key: String, label: String)] {
        var items = baseLegendItems
        items.append((shortcuts.displayString(for: .addTag), "tag"))
        items.append((shortcuts.displayString(for: .copy), "copy"))
        items.append((shortcuts.displayString(for: .pastePlain), "paste plain"))
        items.append((scopeKey, "scope"))
        items.append((shortcuts.displayString(for: .toggleSidebar), "sidebar"))
        items.append((shortcuts.displayString(for: .togglePreview), "preview"))
        return items
    }

    /// Drops the window toggles and the less-used copy/tag/plain-paste
    /// shortcuts, keeps the item actions and scope cycling.
    private var reducedLegendItems: [(key: String, label: String)] {
        var items = baseLegendItems
        items.append((scopeKey, "scope"))
        return items
    }

    /// Guaranteed to fit almost anywhere: navigate + pin only.
    private var minimalLegendItems: [(key: String, label: String)] {
        [
            ("↑↓", "navigate"),
            (shortcuts.displayString(for: .pin), "pin"),
        ]
    }

    /// Shared by the full and reduced tiers: navigate, multi-select, pin,
    /// star, lock, and the two contextual item actions (edit / save image).
    private var baseLegendItems: [(key: String, label: String)] {
        var items: [(key: String, label: String)] = [
            ("↑↓", "navigate"),
            ("⇧↑↓", "multi-select"),
            (shortcuts.displayString(for: .pin), "pin"),
            (shortcuts.displayString(for: .star), "star"),
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

    private var scopeKey: String {
        "\(shortcuts.displayString(for: .previousScope))\(shortcuts.displayString(for: .nextScope))"
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
