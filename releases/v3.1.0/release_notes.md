# Klip v3.1.0

### Added

- **In-app changelog** - Release notes now open inside Klip instead of sending you to GitHub. The post-update "What's New" button opens a proper scrollable window showing the installed version's notes with every earlier release beneath it, and a `Changelog` link in Settings' footer opens the same window any time. The notes are read from a copy of this file bundled inside the app, so it works offline; a "View on GitHub" link is still there as an escape hatch.
- **Image dimensions in the preview** - The preview pane's metadata footer now shows a `Dimensions` row for images, e.g. `3000 × 2000 px`, for both copied images and image files. Pixel counts come from the image's bitmap data rather than its point size, so a Retina screenshot reports its real resolution instead of half of it.
- **Tooltips that actually appear** - Every icon button in the history window has always carried a tooltip string, but macOS never drew them: the window is a borderless non-activating panel, a configuration AppKit's tooltip machinery does not fire in. Klip now draws its own, styled to match the window. Hover any preview-pane action icon - copy, extract text, pin, favorite, lock, save, delete - and you get its name and shortcut.

### Changed

- **The shortcut legend no longer collapses** - Narrowing the window used to make almost every shortcut in the bottom bar vanish at once, leaving `↑↓ navigate  ↩ paste` and a wide empty gap. The legend now drops one shortcut at a time from the least-important end and keeps filling the space it has. `preview`, `sidebar`, `navigate` and `multi-select` were also removed from the list: the first two already have visible buttons in the same bar, and the other two are self-evident.
- **Pane dividers snap to whole points** - Dragging the sidebar or preview divider used to leave the panes on fractional pixel boundaries. Widths are rounded now, matching how an edge resize has always behaved. A drag also no longer writes the new width to disk on every frame - hundreds of writes per drag became a handful.
- **Preview divider is easier to grab** - The drag strip between the list and the preview pane went from 9pt to 12pt, and its resize cursor no longer stops appearing while an image clip is selected. The cursor was being set with a push/pop stack that SwiftUI could unbalance during the image preview's frequent re-layout; it is set outright now, which cannot be unbalanced.
- **Attribution moved out of the interface** - The "based on Buffer by @samirpatil2000" line is gone from Settings. Klip's `LICENSE`, `ATTRIBUTION.md`, and the Clipfield and Pesty licenses now ship inside the app bundle instead, which is what the MIT license actually asks for - previously nothing at all travelled with the binary. Credits remain in the README.

### Removed

- **Quick Paste (⌘1-⌘9)** - Removed along with its nine Settings rows. Those key combinations are now free. Any other shortcuts you rebound are unaffected.

### Known issue

- Dragging the divider between panes makes the moving content flicker. Cosmetic only, and it predates this release. Resizing the window by its edges is unaffected.
