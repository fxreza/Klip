import SwiftUI

/// Right-hand pane: header + action icon cluster, the item preview (or the
/// multi-selection summary), and the tag strip.
struct DetailPane: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var viewModel: HistoryViewModel
    @FocusState.Binding var isTextEditorFocused: Bool
    @FocusState.Binding var isTagInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            // Content preview
            ScrollView {
                ScrollViewReader { proxy in
                    if viewModel.selectionCount > 1 {
                        // Multi-selection summary
                        MultiSelectionSummary(viewModel: viewModel)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else if let item = viewModel.selectedItem {
                        itemContent(item)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .id("editArea")
                            .onChange(of: viewModel.isEditing) { newValue in
                                if newValue {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation {
                                            proxy.scrollTo("editArea", anchor: .top)
                                        }
                                    }
                                }
                            }
                    } else {
                        Text("Select an item")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            // Tag section (single selection only)
            if viewModel.selectionCount <= 1, let item = viewModel.selectedItem {
                Divider()
                TagSection(
                    store: store,
                    viewModel: viewModel,
                    item: item,
                    isTagInputFocused: $isTagInputFocused
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        // Header with count info or type indicator
        HStack {
            Spacer()

            if viewModel.selectionCount > 1 {
                // Multi-selection header
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                    Text("\(viewModel.selectionCount) items selected")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.15))
                .cornerRadius(4)
            } else if let item = viewModel.selectedItem {
                // Single selection header
                if viewModel.isEditing {
                    HStack(spacing: 6) {
                        Text("Editing")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(4)
                } else {
                    HStack(spacing: 6) {
                        Text(item.type == .text ? "Text" : "Image")

                        if item.isFileBacked {
                            Text("Large")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.8))
                                .cornerRadius(4)
                        }

                        if let size = viewModel.itemSize, size > 0 {
                            Text(viewModel.formattedByteCount(size))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
                }
            }

            Spacer()

            // Action buttons - only show for single selection or hide for multi
            if viewModel.selectionCount <= 1 {
                actionIcons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    private var actionIcons: some View {
        HStack(spacing: 12) {
            if let item = viewModel.selectedItem, item.isEditable {
                Button(action: { viewModel.toggleEditMode() }) {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .foregroundColor(viewModel.isEditing ? .blue : .primary)
                .help(viewModel.isEditing ? "Stop editing (auto-saved) (⌘E or Esc)" : "Edit item (⌘E)")
            }

            Button(action: { if let item = viewModel.selectedItem { viewModel.copy(item) } }) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("Copy")

            if viewModel.selectedItem?.type == .image && viewModel.previewImage != nil {
                Button(action: { viewModel.saveSelectedImage() }) {
                    Image(systemName: "arrow.down.to.line")
                }
                .buttonStyle(.plain)
                .help("Save image")
            }

            // OCR button — only for image items without existing OCR text
            if viewModel.selectedItem?.type == .image && viewModel.previewImage != nil && viewModel.selectedItem?.ocrText == nil {
                Button(action: {
                    Task { @MainActor in
                        await viewModel.extractTextFromSelection()
                    }
                }) {
                    Image(systemName: viewModel.isExtractingText ? "ellipsis.circle" : "text.viewfinder")
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isExtractingText)
                .help("Extract Text from Image")
            }

            Button(action: { viewModel.togglePinOnSelection() }) {
                Image(systemName: viewModel.selectedItem?.isPinned == true ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .foregroundColor(viewModel.selectedItem?.isPinned == true ? .accentColor : .secondary)
            .help(viewModel.selectedItem?.isPinned == true ? "Unpin (⌘P)" : "Pin to top (⌘P)")

            Button(action: { viewModel.toggleBookmarkOnSelection() }) {
                Image(systemName: viewModel.selectedItem?.isBookmarked == true ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(.plain)
            .foregroundColor(viewModel.selectedItem?.isBookmarked == true ? .yellow : .secondary)
            .help(viewModel.selectedItem?.isBookmarked == true ? "Remove bookmark (⌘B)" : "Bookmark — protect from deletion (⌘B)")

            Button(action: { viewModel.deleteSelection() }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .foregroundColor(.secondary)
        .font(.system(size: 13))
    }

    // MARK: - Item content

    @ViewBuilder
    private func itemContent(_ item: ClipboardItem) -> some View {
        switch item.type {
        case .text:
            if item.isFileBacked || (item.textContent?.count ?? 0) > 5000 {
                textContent(item)
            } else if viewModel.isEditing {
                TextEditor(text: $viewModel.editText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 200, maxHeight: .infinity)
                    .focused($isTextEditorFocused)
            } else {
                Text(item.textContent ?? "")
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .image:
            VStack(spacing: 12) {
                if let img = viewModel.previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                } else {
                    // Loading placeholder
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: 200)
                }

                // OCR result
                if viewModel.isExtractingText {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 12)
                } else if let ocrText = item.ocrText {
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(height: 0.5)

                        HStack(alignment: .top) {
                            Text(ocrText)
                                .font(.system(size: 13))
                                .textSelection(.enabled)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                            Button(action: { viewModel.copyOCRText(ocrText) }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .help("Copy extracted text")
                        }
                        .padding(.top, 12)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func textContent(_ item: ClipboardItem) -> some View {
        LazyVStack(spacing: 8, pinnedViews: []) {
            Text(viewModel.chunkedText.visibleText)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            if viewModel.chunkedText.isLoadingMore {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 8)
            } else if viewModel.chunkedText.hasMore {
                // This hint fires .onAppear only when it scrolls into view (LazyVStack)
                // That's what triggers the next chunk load
                Text("— \(viewModel.formattedByteCount(viewModel.chunkedText.totalBytes)) total · scroll to load more —")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    .onAppear {
                        Task { await viewModel.loadNextChunk(for: item) }
                    }
            }
        }
    }
}
