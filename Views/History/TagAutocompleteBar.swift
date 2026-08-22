import SwiftUI

/// Horizontal row of tag suggestions, shown while the search field starts with `#`.
struct TagAutocompleteBar: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.tagSuggestions, id: \.self) { tag in
                    Button(action: {
                        viewModel.applyTagFilter(tag)
                    }) {
                        Text("#\(tag)")
                            .font(.system(size: 11))
                            .foregroundColor(TagChip.color(for: tag))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(TagChip.color(for: tag).opacity(0.10))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}
