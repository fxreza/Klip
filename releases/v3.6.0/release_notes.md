# Klip v3.6.0

### Added

- **Quick Look a clip with Space** - Select a clip and press **Space** to open it in the same preview window Finder uses: images at full size, PDFs and documents page by page, and text in a plain reader. Press Space again, or Esc, to close it. Because the search field keeps the keyboard while Klip is open, Space previews only when the search box is empty - once you have typed a query, Space still types a space and **⌘Y** opens the preview instead. ⌘Y always works. A clip holding several files previews all of them, with the preview window's own arrows moving between them. The key is rebindable in Settings → Shortcuts.

### Changed

- **Leaner clip rows, and much lower idle CPU** - Rows no longer show the source app or a live "3 minutes ago" under each clip. Both facts are still in the preview pane, which lists **From** and the exact **Copied** time, and the row now gives the clip's own text the full width. The relative time was also the last thing in Klip that redrew every single second - it kept doing so even with the window closed, which was where roughly two thirds of Klip's idle CPU went. Measured on the same Mac with the window shut, Klip went from about 1.6% of a core down to 0.02%. What is left is the clipboard check itself, and nothing else.

### Installing

Klip is signed with a self-signed certificate, not an Apple Developer ID, so macOS Gatekeeper will not open it on first launch. Unzip it into `/Applications`, then right-click the app and choose **Open**, and confirm once. After that it launches normally. Updating from an earlier Klip through the in-app updater needs no such step.
