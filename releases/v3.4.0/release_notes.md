# Klip v3.4.0

### Added

- **The trash is a place in the window now** - **Trash** sits at the bottom of the history window's sidebar with a live count. Open it and it behaves like any other view of your clips: the same search field, the same `#tag` filter, the same Text / Link / Image / File / Color / Code / Email / Phone chips, the same multi-select. A sort picker above the list orders it by **Date Deleted** (the default), Date Added, Name or Type, and the bar next to it says when clips will be erased automatically. Restore from the row menu, a double-click, `↵`, or the preview pane; erase one clip with `⌘⌫` or the whole trash with **Empty Trash…**, each behind its own confirmation. A trashed clip cannot be edited, tagged, pinned or filed - restore it first, and it comes back with all of that intact.

### Changed

- **A restored clip comes back at the top** - Restoring used to put the clip back where it was when it was deleted, so a clip deleted from a hundred rows down came back a hundred rows down and was hard to find again. It now returns to the top of All, the same way re-copying something already in the history brings it back to the top. Its tags, folder, folder position, pin and favorite all come back with it.
- **Recently Deleted is gone from the menu bar icon** - It listed only the last 25 deletions and could not be searched, sorted, filtered or multi-selected, and anything past the 25th was unreachable. The sidebar's Trash replaces it and does all of that.

### Installing

Klip is signed with a self-signed certificate, not an Apple Developer ID, so macOS Gatekeeper will not open it on first launch. Unzip it into `/Applications`, then right-click the app and choose **Open**, and confirm once. After that it launches normally. Updating from an earlier Klip through the in-app updater needs no such step.
