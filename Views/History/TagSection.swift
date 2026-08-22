import SwiftUI

/// Bottom strip of the detail pane: the selected item's tag chips, the inline
/// "Add tag" input with its suggestion row, and the relative timestamp.
struct TagSection: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var viewModel: HistoryViewModel
    let item: ClipboardItem
    @FocusState.Binding var isTagInputFocused: Bool

    var body: some View {
        let inputSuggestions = viewModel.showTagInput ? viewModel.tagInputSuggestions(excluding: item.tags) : []
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(item.tags, id: \.self) { tag in
                            TagChip(label: tag, onRemove: {
                                viewModel.removeTag(tag, from: item)
                            })
                        }
                        if viewModel.showTagInput {
                            HStack(spacing: 6) {
                                TextField("tag name", text: $viewModel.tagInputText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                                    .focused($isTagInputFocused)
                                    .frame(minWidth: 60)
                                Button("Cancel") {
                                    viewModel.cancelTagInput()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            }
                        } else {
                            Button(action: { viewModel.showTagInput = true }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("Add tag")
                                        .font(.system(size: 11))
                                    Text("⌘T")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary.opacity(0.3))
                                }
                                .foregroundColor(.secondary.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 8)

                RelativeTimestampView(timestamp: item.timestamp)
            }
            if !inputSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(inputSuggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                viewModel.applyTagSuggestion(suggestion, to: item)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(TagChip.color(for: suggestion))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(TagChip.color(for: suggestion).opacity(0.10))
                            .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}
