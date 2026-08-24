# Klip v3.2.0

### Added

- **Choose what syncs** - Settings > Sync has a new **What to Sync** section with a checkbox per kind of clip: Text, Link, Image, File, Color, Code, Email and Phone. An unchecked kind never leaves this Mac and is never taken from your other Macs, so you can keep, say, images and files out of iCloud Drive while text still travels. Everything is checked by default, so sync keeps behaving exactly as before until you change it. Unchecking a kind deletes nothing: clips already here stay here, and copies already on your other Macs stay there.

### Changed

- **The history panel is opaque** - The window was drawn on a translucent material, which let the desktop through and made text hard to read over a dark wallpaper. It now uses a solid background that matches the Settings window in both light and dark mode.
- **Arrow keys move one row** - Holding the down arrow past the last visible row used to scroll half a window at a time, because an off-screen row was centred. A single-row step now scrolls the minimum distance and reveals exactly that row. Clicks on off-screen rows, filter changes and reopening the window still centre, where a big scroll is the point.

### Installing

Klip is signed with a self-signed certificate, not an Apple Developer ID, so macOS Gatekeeper will not open it on first launch. Unzip it into `/Applications`, then right-click the app and choose **Open**, and confirm once. After that it launches normally. Updating from an earlier Klip through the in-app updater needs no such step.
