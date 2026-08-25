# Klip v3.3.0

### Added

- **Deleted clips are recoverable** - Deleting a clip no longer destroys it. It moves to a trash you reach from the menu bar icon > **Recently Deleted**, which lists the last 25 deletions with a preview and how long ago each one went; click one to put it back where it belongs, folder and all. **Empty Trash…** erases everything after a confirmation, and Settings > History > **Trash** chooses how long deleted clips are kept - 7, 30 (the default) or 90 days, or Forever, meaning they only ever go when you empty the trash by hand. The trash stays on the Mac it was deleted on and is never written to iCloud Drive: a delete still reaches your other Macs, but the recoverable copy does not follow it there. Restoring a clip also retracts that delete, so the next sync does not remove it again.
- **Drag clips into any order inside a folder** - Clips in a folder can be dragged up and down into whatever order you want, with an insertion line showing where the drop lands, and multi-select drags move together. The order is saved with the folder and survives relaunch, sync and re-copying the same content. Inside a folder your order wins outright, pins included - a pinned clip stays where you put it instead of jumping to the top. All and Favorites are untouched and stay newest-first with pins on top. A folder you never hand-sort looks exactly as it always did, and clips filed into a folder arrive at the top.

### Changed

- **Copying the same thing twice no longer fills the history with duplicates** - Re-copying content already in the history brings the existing clip back to the top instead of adding a second identical row, however long ago it was captured and whichever app it came from this time. Text, images and files all count: images match on their exact bytes, files on their name and size. The clip keeps everything you gave it - pin, favorite, lock, tags, folder and its position in that folder - and only its date moves. Clips captured before this release are recognised too; Klip works out their content identity in the background on first launch.

### Fixed

- **The menu bar icon could be missing or invisible** - Two separate faults, both in how the status item was created. Under the SwiftUI app lifecycle the item was made before AppKit had finished building the menu bar, so it was registered but never laid out - it reported a frame off the right edge of the screen, drew nothing, and responded only to synthetic clicks. And the icon lost its template flag while being resized, which drew a solid black glyph that was invisible on a dark menu bar while still occupying its slot. The item is now created one run-loop turn later and the flag is set on the final image.
- **A global shortcut macOS had already taken failed silently** - Recording a hotkey that the system owns (or another app had registered first) did nothing at all, with no indication why: macOS refuses the registration and reports only "already exists", never who holds it. Settings > Shortcuts now shows the refusal in red under the shortcut and names the culprit where it can - "Already used by macOS (Spotlight)" - by reading the same shortcut list System Settings shows.

### Installing

Klip is signed with a self-signed certificate, not an Apple Developer ID, so macOS Gatekeeper will not open it on first launch. Unzip it into `/Applications`, then right-click the app and choose **Open**, and confirm once. After that it launches normally. Updating from an earlier Klip through the in-app updater needs no such step.
