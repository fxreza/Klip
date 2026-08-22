import SwiftUI

/// Right-click menu on a clip row.
///
/// Phase 2A ships exactly the actions that already exist elsewhere in the UI
/// (Copy, Pin, Star, Edit, Save Image, Delete) so nothing new is introduced
/// alongside the visual rewrite. Phase 3D extends it with Paste / Paste as
/// Plain Text / Copy as Plain Text / Lock / Move to Folder / Add Tag / Reveal
/// in Finder / Open Link; 3B supplies the "Move to Folder" submenu.
struct RowContextMenu: View {
    @ObservedObject var viewModel: HistoryViewModel
    let item: ClipboardItem

    var body: some View {
        Button("Copy") { viewModel.copy(item) }

        Button(item.isPinned ? "Unpin" : "Pin to Top") {
            viewModel.store.togglePin(for: item)
        }

        Button(item.isBookmarked ? "Remove from Favorites" : "Add to Favorites") {
            viewModel.store.toggleBookmark(for: item)
        }

        if item.isEditable {
            Button("Edit") {
                viewModel.selectSingle(item.id)
                viewModel.enterEditMode()
            }
        }

        if item.type == .image {
            Button("Save Image…") {
                viewModel.saveImage(for: item)
            }
        }

        Divider()

        Button("Delete", role: .destructive) {
            viewModel.delete(item)
        }
        .disabled(item.isLocked)
    }
}
