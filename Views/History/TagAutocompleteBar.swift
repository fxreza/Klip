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
                            .font(.klip(.chip))
                            .foregroundStyle(TagChip.color(for: tag))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(TagChip.color(for: tag).opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}
