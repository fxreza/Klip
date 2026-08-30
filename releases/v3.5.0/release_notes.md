# Klip v3.5.0

### Added

- **Name a clip** - Any clip can now carry a title of your own. The name takes the first line of the row in bold and pushes the clip's own text to a dim second line, so a folder of connection strings, license keys or boilerplate reads as a list of names instead of a wall of near-identical text. Press **F2**, use **Rename…** in the right-click menu, or click the name in the preview pane. Names work on images and files too, which have no editable text of their own. Editing a text clip now has a **Title** field above the content, and both save together. Search matches the name as well as the content, so `⌘F` finds a clip either way. Leaving the field empty removes the name.

### Changed

- **Klip always opens on All** - The sidebar folder and the filter chips at the top now reset every time the window is hidden, so Klip always comes back showing All clips with no kind filter. Before, reopening within about a minute and a half brought back whichever folder or filter was last active - so summoning Klip to paste something you had just copied could open onto a folder that did not contain it, and the clip looked missing. A search you had typed is still kept for a short while, since that is something you may be coming back to.

### Fixed

- **Tags stay reachable in a narrow preview pane** - The tag strip under the preview scrolled sideways, so a couple of long tag names pushed each tag's ✕ and the **Add tag** button off the right edge - in a narrow pane there was no way to add or remove a tag without widening the window first. Tags now wrap onto as many lines as they need, so every ✕ and the Add tag button are always on screen. A single tag too long for even one full line is truncated with its full name on hover, so its ✕ still fits.
- **Clicking the Title field no longer drops you out of editing** - In edit mode, clicking from the content into the Title field ended the edit, so the field could never be typed in. Edit mode now tracks both fields and only saves when focus leaves the editor entirely. Return in the Title field moves down to the content.
- **Tag chips are readable on the selected row** - A tag chip painted its own colour on a faint wash of that same colour, so on the highlighted row it sat on the accent gradient and effectively disappeared - a blue `#work` chip on a blue accent, a green one on green. Chips on the selected row now use white text on a dark pill, which stays legible on all nine accent colours in both light and dark mode. Unselected rows are unchanged and keep their per-tag colours.

### Installing

Klip is signed with a self-signed certificate, not an Apple Developer ID, so macOS Gatekeeper will not open it on first launch. Unzip it into `/Applications`, then right-click the app and choose **Open**, and confirm once. After that it launches normally. Updating from an earlier Klip through the in-app updater needs no such step.
