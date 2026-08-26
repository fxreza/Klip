# Klip

Klip is a fork of Buffer by @samirpatil2000 with a Clipfield-inspired UI, folders, locks, file clips, custom shortcuts, and iCloud Drive sync.

A lightweight, beautiful clipboard manager for macOS with organized history, rich-text support, and seamless cloud sync.

---

## Features

- **Organized History** - Folder-based organization with drag-and-drop; All/Favorites/Folders sidebar
- **No Duplicates** - Re-copying something already in the history brings that clip back to the top instead of adding another row; pins, tags, locks and folder stay with it
- **Manual Folder Order** - Drag clips into any order inside a folder; the order is saved and outranks pins there
- **Trash** - Deleted clips move to a Trash in the sidebar you can search, filter and sort (by date deleted, date added, name or type); restore puts a clip back at the top of All; kept 7/30/90 days or forever, never synced to iCloud
- **Lock & Protect** - Lock individual clips to prevent accidental deletion; folder clips locked by default
- **Clipfield-style UI** - Material panel with sidebar, filter chips, thumbnail badges, metadata footer
- **Rich-text Support** - Capture and paste with formatting (RTF/HTML); explicit "Paste as Plain Text" option
- **File Clips** - Capture any file with automatic copying (configurable size cap), previews via QuickLook, save to disk
- **Content Filters** - Filter by type: Text, Link, Image, File, Color, Code, Email, Phone
- **Custom Shortcuts** - Rebind every action in Settings; no conflicts allowed
- **iCloud Drive Sync** - Automatic sync across devices with per-device snapshots; optional, disabled by default
- **Multi-select & Multi-paste** - Select multiple items and paste as one; paste files into Finder
- **Search & Tags** - Full-text search including OCR text, tags, source app, and file names
- **Pin & Star** - Pin favorites to keep them at the top; star for quick filtering
- **Inline Editing** - Edit text/code snippets directly in the app; auto-saves to clipboard
- **History Limit** - Configurable 1K / 5K / 10K / Unlimited; locked items never evicted
- **Permissions panel** - shows exactly what Klip needs (only Accessibility, for auto-paste) with one-click access to System Settings

---

## Requirements

- macOS 13.0 or later
- Accessibility permission for auto-paste into other apps (the global hotkey works without it; Klip asks on first launch)

---

## Installation

Download from [GitHub Releases](https://github.com/fxreza/Klip/releases).

1. Download `Klip_Universal.zip` (Apple Silicon + Intel) - or the `.dmg` files when a notarized build is published
2. Unzip and drag **Klip.app** to your **Applications** folder
3. Launch Klip - it appears in the menu bar
4. First launch prompts for Accessibility permission; grant it to enable the hotkey and auto-paste
5. **Gatekeeper note**: The build is signed with a local identity and not notarized. Right-click Klip.app and select "Open" the first time to bypass the warning.

History and settings are migrated automatically from Buffer on first launch; Buffer's data is left untouched in `~/Library/Application Support/Buffer`.

---

## Usage

| Shortcut | Action |
|----------|--------|
| `⇧⌘V` | Toggle clipboard history |
| `↑` / `↓` | Navigate items |
| `⇧↑` / `⇧↓` | Extend selection (multi-select) |
| `⌘`-click | Toggle a row in the selection |
| `⇧`-click | Extend the selection to the clicked row |
| `↵` Enter | Paste selected item(s) (in the Trash: restore them) |
| `⌘C` | Copy selected item text |
| `⌘P` | Pin / unpin (float to top) |
| `⌘B` | Star / unstar |
| `⌘T` | Add tag (or `#tag` in search) |
| `⌘S` | Save image to disk |
| `⌘⌫` | Delete selected item(s) - recoverable from the Trash (in the Trash: delete permanently) |
| `⎋` Esc | Close history window |

All shortcuts are rebindable in Settings > Shortcuts.

---

## Data

- **Location**: `~/Library/Application Support/Klip`
- **Format**: JSON-based (history.json, folders.json, trash.json) + image/text/file/flavor storage
- **Local-only by default** - no network access unless iCloud Drive sync is enabled
- **Deleted clips**: kept in `trash.json` with their assets until the retention window (Settings > History > Trash) expires or you empty the trash; browse them under **Trash** in the history window's sidebar; local to this Mac either way
- **Sync**: Optional iCloud Drive sync (disabled by default); enable in Settings > Sync
  - Synced data: history, folders, locks, tags, images/text/files
  - Not synced: the trash - a delete propagates as a tombstone, the recoverable copy stays on the Mac it was deleted on
  - Per-device snapshots prevent conflicts; delete operations sync via tombstones
  - Large files (default >50 MB) stay local-only with a reference

---

## iCloud Sync

When enabled, clipboard history syncs across your Macs via iCloud Drive.

- **Enable**: Settings > Sync (requires iCloud Drive in `~/Library/Mobile Documents`)
- **How it works**: Per-device snapshot files + content-hash deduplication + tombstones for deletes
- **Limitations**: Requires network for sync; changes may take up to 30 seconds to appear on other devices; the trash is never synced
- **Disabling**: Turn off in Settings; data stays local-only (no back-sync from remote)

---

## Build from Source

```bash
# Clone the repository
git clone https://github.com/fxreza/Klip.git
cd Klip

# Build (ad-hoc signed, no .env needed)
sh scripts/build_local.sh

# Run tests
sh scripts/run_tests.sh

# Build DMG (requires .env with notarization credentials; otherwise ad-hoc)
sh build_dmg.sh

# Release build
sh scripts/release.sh
```

See `RELEASE.md` for detailed steps.

---

## Credits

- **Buffer** - Original app by Samir Patil (@samirpatil2000), MIT license
- **Clipfield** - UI design and theme tokens by Alex Jolley, MIT license
- **Pesty** - iCloud Drive sync approach by Moamen Basel, MIT license

---

## License

MIT License - see LICENSE file for details.
