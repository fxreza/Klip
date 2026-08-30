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
    /// Edit mode's title field. Tracked separately from the body editor so
    /// clicking between the two does not read as "left the editor".
    @FocusState.Binding var isEditTitleFocused: Bool
    @FocusState.Binding var isTagInputFocused: Bool

    /// Matches `SearchBar`'s top padding. 3.0.1 made the pane a full-height
    /// sibling of the sidebar (it used to be boxed between the chip bar and
    /// the action bar), so its header now sits at the top of the window and
    /// has to line up with the search field rather than with a divider.
    static let topPadding: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.selectionCount > 1 {
                multiSelectionHeader
                    .padding(.horizontal, 16)
                    .padding(.top, Self.topPadding)
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
                    .padding(.top, Self.topPadding)
                    .padding(.bottom, item.displayTitle == nil || viewModel.isEditing ? 12 : 6)

                if let name = item.displayTitle, !viewModel.isEditing {
                    titleStrip(name, for: item)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

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

    @ViewBuilder
    private func actionIcons(for item: ClipboardItem) -> some View {
        // 5E: a trashed clip has two things worth doing to it, and every
        // other icon here would write to `store.items`, where it no longer is.
        if viewModel.isTrashScope {
            trashActionIcons(for: item)
        } else {
            historyActionIcons(for: item)
        }
    }

    private func trashActionIcons(for item: ClipboardItem) -> some View {
        HStack(spacing: 12) {
            iconButton(
                "arrow.uturn.backward",
                tint: Theme.accent,
                help: "Restore to the top of All (\(ShortcutManager.shared.displayString(for: .paste)))"
            ) {
                viewModel.restore(item)
            }

            iconButton("doc.on.doc", tint: .secondary, help: "Copy") {
                viewModel.copy(item)
            }

            iconButton(
                "trash.slash",
                tint: .secondary,
                help: "Delete permanently (\(ShortcutManager.shared.displayString(for: .delete)))"
            ) {
                viewModel.requestPurge(ids: [item.id])
            }
        }
    }

    private func historyActionIcons(for item: ClipboardItem) -> some View {
        HStack(spacing: 12) {
            if item.isEditable {
                iconButton(
                    "square.and.pencil",
                    tint: viewModel.isEditing ? Theme.accent : .secondary,
                    help: viewModel.isEditing
                        ? "Stop editing (auto-saved) (\(ShortcutManager.shared.displayString(for: .edit)) or \(ShortcutManager.shared.displayString(for: .escape)))"
                        : "Edit item (\(ShortcutManager.shared.displayString(for: .edit)))"
                ) { viewModel.toggleEditMode() }
            }

            iconButton("doc.on.doc", tint: .secondary, help: "Copy") {
                viewModel.copy(item)
            }

            if item.type == .image && viewModel.previewImage != nil {
                iconButton("arrow.down.to.line", tint: .secondary, help: "Save image (\(ShortcutManager.shared.displayString(for: .saveToDisk)))") {
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
                help: item.isPinned
                    ? "Unpin (\(ShortcutManager.shared.displayString(for: .pin)))"
                    : "Pin to top (\(ShortcutManager.shared.displayString(for: .pin)))"
            ) { viewModel.togglePinOnSelection() }

            iconButton(
                item.isBookmarked ? "star.fill" : "star",
                tint: item.isBookmarked ? Theme.bookmarkTint : .secondary,
                help: item.isBookmarked
                    ? "Unfavorite (\(ShortcutManager.shared.displayString(for: .star)))"
                    : "Favorite — protects from cleanup (\(ShortcutManager.shared.displayString(for: .star)))"
            ) { viewModel.toggleBookmarkOnSelection() }

            iconButton(
                item.isLocked ? "lock.fill" : "lock.open",
                tint: item.isLocked ? Theme.lockTint : .secondary,
                help: "\(item.isLocked ? "Unlock" : "Lock") (\(ShortcutManager.shared.displayString(for: .lock)))"
            ) { viewModel.toggleLockSelection() }

            iconButton("trash", tint: .secondary, help: item.isLocked ? "Locked - unlock to delete" : "Delete (\(ShortcutManager.shared.displayString(for: .delete)))") {                viewModel.deleteSelection()
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
        .klipHelp(help)
    }

    // MARK: - Title

    /// The clip's name, shown under the kind header when it has one. Click to
    /// rename — the same inline card F2 and the row menu open.
    private func titleStrip(_ name: String, for item: ClipboardItem) -> some View {
        Button {
            viewModel.requestRenameClip(id: item.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "text.cursor")
                    .font(Theme.icon(11, preview: true))
                    .foregroundStyle(.tertiary)
                Text(name)
                    .font(.klip(.preview))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isTrashScope)
        .klipHelp(viewModel.isTrashScope
                  ? "Restore the clip to rename it"
                  : "Rename (\(ShortcutManager.shared.displayString(for: .renameClip)))")
    }

    /// Edit mode's title field. Sits above the body editor and commits with
    /// it; leaving it empty removes the name.
    private var editTitleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TITLE")
                .font(.klip(.caption))
                .fontWeight(.semibold)
                .kerning(0.6)
                .foregroundStyle(.secondary)
            TextField("Name this clip (optional)", text: $viewModel.editTitleText)
                .textFieldStyle(.plain)
                .font(.klip(.preview))
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isEditTitleFocused ? Theme.accent : Theme.hairline, lineWidth: 1)
                )
                .focused($isEditTitleFocused)
                // Return moves to the body rather than committing, so the
                // title can be typed and the text edited in one pass.
                .onSubmit { isTextEditorFocused = true }
        }
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
            VStack(alignment: .leading, spacing: 6) {
                editTitleField
                    .padding(.bottom, 4)

                TextEditor(text: $viewModel.editText)
                    .font(.klip(.previewMono))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 200, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
                    .focused($isTextEditorFocused)

                // Phase 3D deliverable 3: editing a rich item saves plain
                // text and drops its RTF/flavors on commit.
                if item.rtfFilename != nil || item.flavorsFilename != nil {
                    Text("Editing keeps plain text only — formatting will be dropped when you save.")
                        .font(.klip(.caption))
                        .foregroundStyle(.secondary)
                }
            }
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

                        // The tappable area used to be the glyph's own
                        // painted pixels — a ~12 pt target with no padding
                        // and no `contentShape`, which is half of why this
                        // button "did nothing" (user item 11).
                        Button(action: { viewModel.copyOCRText(ocrText) }) {
                            Image(systemName: "doc.on.doc")
                                .font(Theme.icon(12, preview: true))
                                .foregroundStyle(.secondary)
                                .padding(5)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .klipHelp("Copy extracted text")
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    /// `.file` item preview: a static QuickLook *thumbnail* of the first file
    /// (pane width × 320 pt) above the fallback card — icon, name(s), size,
    /// kind, a "Reference" badge for files that were only referenced (not
    /// copied in), a "File not found" badge, and Reveal in Finder / Open.
    ///
    /// 3.0.1: the live `QLPreviewView` that used to sit at the top is gone.
    /// Setting its preview item from `updateNSView` — i.e. from inside a
    /// SwiftUI layout pass — hits a QuickLook assertion that aborts the
    /// process (three user crash reports on 3.0.0). Nothing in this path
    /// touches a QuickLook UI class any more; see `FilePreview.swift`.
    @ViewBuilder
    private func fileBody(_ item: ClipboardItem) -> some View {
        let attachment = item.fileAttachment
        let fileURL = store.fileURLs(for: item).first
        let isMissing = store.fileIsMissing(item)

        VStack(alignment: .leading, spacing: 10) {
            if let fileURL, !isMissing {
                FileThumbnailView(url: fileURL, itemID: item.id, maxHeight: 320)
            }

            fileFallbackCard(item, attachment: attachment, fileURL: fileURL, isMissing: isMissing)

            HStack(spacing: 8) {
                if attachment?.isReference == true {
                    Text("Reference — original file")
                        .font(.klip(.badge))
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.chipInactive))
                }
                if isMissing {
                    Text("File not found")
                        .font(.klip(.badge))
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.destructive)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.destructive.opacity(0.12)))
                }

                Spacer(minLength: 0)

                if let fileURL, !isMissing {
                    Button(action: { NSWorkspace.shared.open(fileURL) }) {
                        Label("Open", systemImage: "arrow.up.forward.app")
                            .font(.klip(.caption))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                if let fileURL {
                    Button(action: { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }) {
                        Label("Reveal in Finder", systemImage: "folder")
                            .font(.klip(.caption))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    /// Name / size / kind block. The big icon is only drawn when there is no
    /// thumbnail above it, so a previewable file doesn't show its artwork
    /// twice.
    @ViewBuilder
    private func fileFallbackCard(
        _ item: ClipboardItem,
        attachment: FileAttachment?,
        fileURL: URL?,
        isMissing: Bool
    ) -> some View {
        let showIcon = fileURL == nil || isMissing

        VStack(spacing: 10) {
            if showIcon {
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
                .opacity(isMissing ? 0.5 : 1)
            }

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

            if let kind = FilePreview.kindLabel(for: fileURL, name: attachment?.originalName) {
                Text(kind)
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
                // Sits under Size because the two answer the same question
                // ("how big is this?") from different angles. Unlike the rows
                // around it there is no "—" fallback: most clips are text and
                // have no dimensions, so a permanent em dash would be noise,
                // and for images the value arrives a moment after selection —
                // a row that appears reads better than one that changes.
                if let dimensions = viewModel.previewDimensions {
                    metaRow("Dimensions", value: dimensions.displayString)
                }
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
