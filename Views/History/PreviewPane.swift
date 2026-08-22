// Adapted from Clipfield (MIT, Copyright 2026 Alex Jolley) —
// UI/Overlay/ClipPreviewPane.swift.

import SwiftUI
import AppKit

/// Right-hand detail pane. Replaces `Views/History/DetailPane.swift`.
///
/// Layout follows Clipfield: a kind header with the action cluster, a rich
/// body (image / colour swatch / text / file placeholder), and a metadata
/// footer. Everything Buffer already did is preserved — chunked loading of
/// large text, inline edit mode, OCR, the multi-selection summary and the tag
/// strip with its add-tag input (now part of the footer).
struct PreviewPane: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var viewModel: HistoryViewModel
    @FocusState.Binding var isTextEditorFocused: Bool
    @FocusState.Binding var isTagInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.selectionCount > 1 {
                multiSelectionHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                ScrollView {
                    MultiSelectionSummary(viewModel: viewModel)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                Spacer(minLength: 0)
            } else if let item = viewModel.selectedItem {
                header(for: item)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                ScrollView {
                    ScrollViewReader { proxy in
                        body(for: item)
                            .padding(.horizontal, 16)
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
                    }
                }

                Spacer(minLength: 0)

                footer(for: item)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.18), value: viewModel.selectedItem?.id)
    }

    // MARK: - Header

    private var multiSelectionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Theme.multiSelectTint)
            Text("\(viewModel.selectionCount) items selected")
                .font(.klip(.sidebarTitle))
                .fontWeight(.semibold)
            Spacer(minLength: 0)
        }
    }

    /// Kind + badges on the left, the action cluster on the right. With eight
    /// possible buttons the row does not always fit a 200pt-wide preview pane,
    /// so it falls back to stacking the actions under the title rather than
    /// wrapping the kind label mid-word.
    private func header(for item: ClipboardItem) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                headerTitle(for: item)
                Spacer(minLength: 6)
                actionIcons(for: item)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    headerTitle(for: item)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    actionIcons(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func headerTitle(for item: ClipboardItem) -> some View {
        Image(systemName: item.displayKind.systemImage)
            .foregroundStyle(Theme.kindTint(item.displayKind))
        Text(viewModel.isEditing ? "Editing" : item.displayKind.label)
            .font(.klip(.sidebarTitle))
            .fontWeight(.semibold)
            .foregroundStyle(viewModel.isEditing ? Theme.accent : Color.primary)
            .lineLimit(1)
            .fixedSize()

        if item.isFileBacked {
            Text("Large")
                .font(.klip(.badge))
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.largeBadgeTint.opacity(0.8)))
                .fixedSize()
        }

        if let size = viewModel.itemSize, size > 0 {
            Text(viewModel.formattedByteCount(size))
                .font(.klip(.caption))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func actionIcons(for item: ClipboardItem) -> some View {
        HStack(spacing: 12) {
            if item.isEditable {
                iconButton(
                    "square.and.pencil",
                    tint: viewModel.isEditing ? Theme.accent : .secondary,
                    help: viewModel.isEditing ? "Stop editing (auto-saved) (⌘E or Esc)" : "Edit item (⌘E)"
                ) { viewModel.toggleEditMode() }
            }

            iconButton("doc.on.doc", tint: .secondary, help: "Copy") {
                viewModel.copy(item)
            }

            if item.type == .image && viewModel.previewImage != nil {
                iconButton("arrow.down.to.line", tint: .secondary, help: "Save image (⌘S)") {
                    viewModel.saveSelectedImage()
                }
            }

            // OCR — only for image items without existing OCR text.
            if item.type == .image && viewModel.previewImage != nil && item.ocrText == nil {
                iconButton(
                    viewModel.isExtractingText ? "ellipsis.circle" : "text.viewfinder",
                    tint: .secondary,
                    help: "Extract Text from Image"
                ) {
                    Task { @MainActor in await viewModel.extractTextFromSelection() }
                }
                .disabled(viewModel.isExtractingText)
            }

            iconButton(
                item.isPinned ? "pin.fill" : "pin",
                tint: item.isPinned ? Theme.pinTint : .secondary,
                help: item.isPinned ? "Unpin (⌘P)" : "Pin to top (⌘P)"
            ) { viewModel.togglePinOnSelection() }

            iconButton(
                item.isBookmarked ? "star.fill" : "star",
                tint: item.isBookmarked ? Theme.bookmarkTint : .secondary,
                help: item.isBookmarked ? "Remove from Favorites (⌘B)" : "Add to Favorites — protects from cleanup (⌘B)"
            ) { viewModel.toggleBookmarkOnSelection() }

            iconButton(
                item.isLocked ? "lock.fill" : "lock.open",
                tint: item.isLocked ? Theme.lockTint : .secondary,
                help: item.isLocked ? "Unlock (⌘L)" : "Lock (⌘L)"
            ) { viewModel.toggleLockSelection() }

            iconButton("trash", tint: .secondary, help: item.isLocked ? "Locked - unlock to delete" : "Delete (⌘⌫)") {
                viewModel.deleteSelection()
            }
            .disabled(item.isLocked)
        }
    }

    private func iconButton(_ systemImage: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.icon(13, preview: true))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Body

    @ViewBuilder
    private func body(for item: ClipboardItem) -> some View {
        switch item.type {
        case .text:
            textBody(item)
        case .image:
            imageBody(item)
        case .file:
            fileBody(item)
        }
    }

    @ViewBuilder
    private func textBody(_ item: ClipboardItem) -> some View {
        if let swatch = item.swatchColor, !viewModel.isEditing {
            colorBody(item, swatch: swatch)
        } else if item.isFileBacked || (item.textContent?.count ?? 0) > 5000 {
            chunkedText(item)
        } else if viewModel.isEditing {
            TextEditor(text: $viewModel.editText)
                .font(.klip(.previewMono))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 200, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
                .focused($isTextEditorFocused)
        } else {
            Text(item.textContent ?? "")
                .font(.klip(item.displayKind == .code ? .previewMono : .preview))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func colorBody(_ item: ClipboardItem, swatch: Color) -> some View {
        let text = (item.textContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 14)
                .fill(swatch)
                .frame(height: 130)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.swatchStroke, lineWidth: 1))
                .shadow(color: swatch.opacity(0.5), radius: 10, y: 4)
            Text(text.uppercased())
                .font(.klip(.previewMono))
                .fontWeight(.semibold)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func imageBody(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let img = viewModel.previewImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline, lineWidth: 1))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: 200)
            }

            if viewModel.isExtractingText {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 12)
            } else if let ocrText = item.ocrText {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 0.5)

                    HStack(alignment: .top, spacing: 8) {
                        Text(ocrText)
                            .font(.klip(.preview))
                            .textSelection(.enabled)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                        Button(action: { viewModel.copyOCRText(ocrText) }) {
                            Image(systemName: "doc.on.doc")
                                .font(Theme.icon(12, preview: true))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy extracted text")
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    /// Placeholder shown for `.file` items. Phase 3F replaces this with a
    /// `QLPreviewView` / `QLThumbnailGenerator` preview.
    private func fileBody(_ item: ClipboardItem) -> some View {
        let attachment = item.fileAttachment
        return VStack(spacing: 10) {
            Group {
                if let icon = item.fileIcon(store: store) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "doc")
                        .font(Theme.icon(46, preview: true))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 72, height: 72)

            Text(attachment?.originalName ?? "File")
                .font(.klip(.preview))
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let extra = attachment?.additionalNames, !extra.isEmpty {
                Text("+\(extra.count) more file\(extra.count == 1 ? "" : "s")")
                    .font(.klip(.caption))
                    .foregroundStyle(.secondary)
            }

            if let bytes = attachment?.byteSize, bytes > 0 {
                Text(viewModel.formattedByteCount(Int(bytes)))
                    .font(.klip(.caption))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func chunkedText(_ item: ClipboardItem) -> some View {
        LazyVStack(spacing: 8, pinnedViews: []) {
            Text(viewModel.chunkedText.visibleText)
                .font(.klip(.previewMono))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            if viewModel.chunkedText.isLoadingMore {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 8)
            } else if viewModel.chunkedText.hasMore {
                // Fires .onAppear only when it scrolls into view (LazyVStack),
                // which is what triggers the next chunk load.
                Text("— \(viewModel.formattedByteCount(viewModel.chunkedText.totalBytes)) total · scroll to load more —")
                    .font(.klip(.caption))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    .onAppear {
                        Task { await viewModel.loadNextChunk(for: item) }
                    }
            }
        }
    }

    // MARK: - Footer

    private func footer(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            VStack(alignment: .leading, spacing: 5) {
                metaRow("Copied", value: item.timestamp.formatted(date: .abbreviated, time: .shortened))
                metaRow("From", value: item.sourceApp ?? "—")
                metaRow("Size", value: viewModel.itemSize.map { viewModel.formattedByteCount($0) } ?? "—")
                metaRow("Folder", value: folderName(for: item))
            }
            .padding(.horizontal, 16)

            TagSection(
                store: store,
                viewModel: viewModel,
                item: item,
                isTagInputFocused: $isTagInputFocused
            )
        }
        .padding(.bottom, 12)
    }

    private func folderName(for item: ClipboardItem) -> String {
        guard let id = item.folderID else { return "—" }
        return store.folders.first(where: { $0.id == id })?.name ?? "—"
    }

    private func metaRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.klip(.caption))
    }

    // MARK: - Empty state

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(Theme.icon(30, preview: true))
                .foregroundStyle(.tertiary)
            Text("Select an item")
                .font(.klip(.preview))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
