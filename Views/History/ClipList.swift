import SwiftUI
import AppKit

/// The scrolling list of clips. Replaces `Views/ClipboardListView.swift`.
///
/// **Click semantics are unchanged from Buffer and must stay that way**
/// (Clipfield's single-click-pastes is explicitly not adopted):
/// - single click → select only, via the `ClickModifierDetector` overlay so the
///   ⌘ / ⇧ modifiers are visible;
/// - ⌘-click toggles, ⇧-click extends from the anchor;
/// - double-click → copy to the clipboard and close the window;
/// - nothing here ever pastes.
struct ClipList: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var viewModel: HistoryViewModel

    @State private var hoveredID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 3) {
                    let items = viewModel.filteredItems

                    if items.contains(where: { $0.isPinned }) {
                        pinnedHeader
                    }

                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        // Separator between the pinned group and the rest.
                        if !item.isPinned && index > 0 && items[index - 1].isPinned {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: 0.5)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                        }

                        row(item, at: index)
                    }
                }
                .padding(8)
            }
            .onChange(of: viewModel.scrollTrigger) { trigger in
                // `scrollTrigger` is the "this selection move came from the
                // keyboard / a scope switch" flag. Driving the scroll off it
                // (rather than off `selectedIndex`) also covers the case where
                // the new selection lands on the index it already had — a scope
                // or chip change that snaps back to row 0.
                guard trigger else { return }
                if let item = viewModel.filteredItems[safe: viewModel.selectedIndex] {
                    withAnimation(Theme.selectionSpring) {
                        proxy.scrollTo(item.id)
                    }
                }
                viewModel.scrollTrigger = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .bufferWindowDidOpen)) { _ in
                // Bring the restored / default selection into view on reopen.
                let scrollTarget = viewModel.selectedID ?? viewModel.filteredItems.first?.id
                if let id = scrollTarget {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Pieces

    private var pinnedHeader: some View {
        HStack(spacing: 4) {
            Image(systemName: "pin.fill")
                .rotationEffect(.degrees(40))
            Text("Pinned")
        }
        .font(.klip(.sectionHeader))
        .fontWeight(.bold)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: ClipboardItem, at index: Int) -> some View {
        ClipRow(
            item: item,
            store: store,
            isPrimarySelection: item.id == viewModel.selectedID,
            isMultiSelected: viewModel.selectedIDs.contains(item.id) && item.id != viewModel.selectedID,
            isHovered: hoveredID == item.id,
            // Unchanged: tapping a row's tag chip sets the filter and nothing else.
            onTagTap: { tag in viewModel.activeTagFilter = tag }
        )
        .id(item.id)
        .contentShape(Rectangle())
        .overlay(
            ClickModifierDetector { modifiers in
                viewModel.selectedIndex = index

                if modifiers.hasCommand {
                    viewModel.toggleSelection(item.id)
                } else if modifiers.hasShift {
                    viewModel.extendSelectionTo(item.id)
                } else {
                    viewModel.selectSingle(item.id)
                }
            },
            alignment: .center
        )
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded { _ in
                    // Handled by ClickModifierDetector — kept so the
                    // double-click recogniser has a single-tap sibling.
                }
        )
        .highPriorityGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    viewModel.selectedIndex = index
                    viewModel.copy(item)
                    viewModel.onDismiss()
                }
        )
        .onHover { hovering in
            if hovering {
                hoveredID = item.id
            } else if hoveredID == item.id {
                hoveredID = nil
            }
        }
        .contextMenu {
            RowContextMenu(viewModel: viewModel, item: item)
        }
    }
}
