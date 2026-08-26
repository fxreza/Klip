import SwiftUI

/// Preview-pane footer strip: the selected item's tag chips, the inline
/// "Add tag" input with its suggestion row, and the relative timestamp.
struct TagSection: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var viewModel: HistoryViewModel
    let item: ClipboardItem
    @FocusState.Binding var isTagInputFocused: Bool

    var body: some View {
        let inputSuggestions = viewModel.showTagInput ? viewModel.tagInputSuggestions(excluding: item.tags) : []
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(item.tags, id: \.self) { tag in
                            // 5E: a trashed clip's tags are shown but not
                            // editable — the write would go to `store.items`,
                            // where the clip no longer is. Restore it to
                            // change its tags.
                            TagChip(label: tag, onRemove: viewModel.isTrashScope ? nil : {
                                viewModel.removeTag(tag, from: item)
                            })
                        }
                        if viewModel.isTrashScope {
                            EmptyView()
                        } else if viewModel.showTagInput {
                            HStack(spacing: 6) {
                                TextField("tag name", text: $viewModel.tagInputText)
                                    .textFieldStyle(.plain)
                                    .font(.klip(.chip))
                                    .focused($isTagInputFocused)
                                    .frame(minWidth: 60)
                                Button("Cancel") {
                                    viewModel.cancelTagInput()
                                }
                                .buttonStyle(.plain)
                                .font(.klip(.chip))
                                .foregroundStyle(.secondary)
                            }
                        } else {
                            Button(action: { viewModel.showTagInput = true }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.klip(.badge))
                                        .fontWeight(.bold)
                                    Text("Add tag")
                                        .font(.klip(.chip))
                                    Text("⌘T")
                                        .font(.klip(.caption))
                                        .foregroundStyle(.quaternary)
                                }
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 8)

                RelativeTimestampView(timestamp: item.timestamp, role: .caption, color: .secondary)
            }
            if !inputSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(inputSuggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                viewModel.applyTagSuggestion(suggestion, to: item)
                            }
                            .buttonStyle(.plain)
                            .font(.klip(.badge))
                            .foregroundStyle(TagChip.color(for: suggestion))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(TagChip.color(for: suggestion).opacity(0.10)))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}
