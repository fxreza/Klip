import SwiftUI
import AppKit

/// Right-click menu on a clip row (Phase 3D — full rewrite of the Phase 2A
/// version, which only had Copy / Pin / Star / Edit / Save Image / Delete).
///
/// Right-clicking a row that isn't part of the current selection selects it
/// first (`ClipList`'s `.contextMenu` calls `viewModel.selectForContextMenu`
/// before building this view); right-clicking inside an existing
/// multi-selection leaves it intact, so bulk actions (Move to Folder, Lock,
/// Delete, Save to Disk) apply to the whole thing. Per-item actions (Edit,
/// Add Tag, Reveal in Finder, Open Link) always target the row that was
/// actually clicked (`item`).
///
/// Key equivalents shown in parentheses come from `ShortcutManager`, so a
/// rebind in Settings > Shortcuts is reflected here too. They are plain text,
/// not real SwiftUI `.keyboardShortcut`s — the actual key handling stays in
/// `GlobalKeyMonitor` so a menu item never double-fires alongside it.
struct RowContextMenu: View {
    @ObservedObject var viewModel: HistoryViewModel
    let item: ClipboardItem

    private var isMultiSelection: Bool { viewModel.selectedItems.count > 1 }

    var body: some View {
        Button(shortcutLabel("Paste", .paste)) {
            viewModel.pasteFromMenu(item, mode: viewModel.defaultPasteMode)
        }
        Button(shortcutLabel(pastePlainTitle, .pastePlain)) {
            viewModel.pasteFromMenu(item, mode: viewModel.alternatePasteMode)
        }

        Button(shortcutLabel("Copy", .copy)) {
            viewModel.copyFromMenu(item, mode: viewModel.defaultPasteMode)
        }
        Button(shortcutLabel(copyPlainTitle, .copyPlain)) {
            viewModel.copyFromMenu(item, mode: viewModel.alternatePasteMode)
        }

        Divider()

        if item.isEditable {
            Button(shortcutLabel("Edit", .edit)) {
                viewModel.selectSingle(item.id)
                viewModel.enterEditMode()
            }
        }

        Button(shortcutLabel(item.isPinned ? "Unpin" : "Pin to Top", .pin)) {
            viewModel.store.togglePin(for: item)
        }

        Button(shortcutLabel(item.isBookmarked ? "Remove from Favorites" : "Add to Favorites", .star)) {
            viewModel.store.toggleBookmark(for: item)
        }

        Button(shortcutLabel(item.isLocked ? "Unlock" : "Lock", .lock)) {
            viewModel.toggleLockSelection()
        }

        Menu("Move to Folder") {
            ForEach(viewModel.store.folders) { folder in
                Button(folder.name) {
                    viewModel.moveSelection(toFolder: folder.id)
                }
            }
            if item.folderID != nil {
                if !viewModel.store.folders.isEmpty { Divider() }
                Button("Remove from Folder") {
                    viewModel.moveSelection(toFolder: nil)
                }
            }
        }

        Button(shortcutLabel("Add Tag…", .addTag)) {
            viewModel.selectSingle(item.id)
            viewModel.keyAddTag()
        }

        Divider()

        Button(shortcutLabel("Save to Disk…", .saveToDisk)) {
            if isMultiSelection {
                viewModel.saveAllSelected()
            } else {
                viewModel.saveSelectedToDisk()
            }
        }

        if item.type == .file {
            Button("Reveal in Finder") {
                if let url = viewModel.store.fileURLs(for: item).first {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }

        if item.displayKind == .link {
            Button("Open Link") {
                viewModel.openLink(item)
            }
        }

        Divider()

        Button(deleteTitle, role: .destructive) {
            if isMultiSelection {
                viewModel.deleteSelectedItems()
            } else {
                viewModel.delete(item)
            }
        }
        .disabled(!isMultiSelection && item.isLocked)
    }

    /// "Paste as Plain Text" swaps to "Paste with Formatting" once "Always
    /// paste as plain text" makes the default paste plain — the alternate
    /// action still does the opposite of the default, only the label changes.
    private var pastePlainTitle: String {
        viewModel.alternatePasteMode == .rich ? "Paste with Formatting" : "Paste as Plain Text"
    }

    private var copyPlainTitle: String {
        viewModel.alternatePasteMode == .rich ? "Copy with Formatting" : "Copy as Plain Text"
    }

    private var deleteTitle: String {
        guard !isMultiSelection, item.isLocked else { return shortcutLabel("Delete", .delete) }
        return "Delete (Locked)"
    }

    private func shortcutLabel(_ title: String, _ action: ShortcutAction) -> String {
        "\(title) (\(ShortcutManager.shared.displayString(for: action)))"
    }
}
