import SwiftUI

/// Top bar: active tag chip, search field, clear button, item count.
struct SearchBar: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var viewModel: HistoryViewModel
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary.opacity(0.7))
                .font(.system(size: 13, weight: .medium))

            if let tag = viewModel.activeTagFilter {
                HStack(spacing: 3) {
                    Text("#\(tag)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(TagChip.color(for: tag))
                    Button(action: { viewModel.activeTagFilter = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(TagChip.color(for: tag).opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(TagChip.color(for: tag).opacity(0.12))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(TagChip.color(for: tag).opacity(0.2), lineWidth: 0.5))
            }

            TextField(store.allTags.isEmpty ? "Search clipboard…" : "Search or #tag…", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)

            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.5))
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Item count
            Text("\(viewModel.filteredItems.count) items")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color(NSColor.controlBackgroundColor)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.primary.opacity(0.15)),
                    alignment: .bottom
                )
        )
    }
}
