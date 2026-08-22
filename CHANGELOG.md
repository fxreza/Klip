# Changelog

All notable changes to Klip are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## 3.0.0 (2026-08-22)

### Added

- **Folders** - Organize clips into user-created folders; drag and drop clips into folders; empty folders can be deleted immediately, non-empty folders require confirmation
- **Lock / Protect** - Lock individual clips to prevent accidental deletion; clips moved into folders are locked by default; locked clips immune to delete, clear history, and bulk cleanup; unlock via context menu or preview pane button
- **Clipfield-style UI** - Material panel (`.regularMaterial`, 18pt radius) with borderless design, floating above other windows; persistent window size and position
- **Sidebar Navigation** - All / Favorites (starred items) / Folders with live counts; collapsible 120-320pt; accent-gradient selection with animation
- **Filter Chips** - Filter by content type: Text / Link / Image / File / Color / Code / Email / Phone; detection runs at capture time with lazy backfill for existing items
- **Rich-text Support** - Capture RTF/HTML and raw pasteboard flavors; explicit "Paste as Plain Text" (⌥↩ / ⇧⌘↩) or via settings
- **File Clips** - Capture files of any type with automatic copying (default 50 MB cap, configurable); thumbnails via QuickLookThumbnailing; preview pane integration; save single/multiple to disk; reference + bookmark for files above cap
- **Content Detection** - Link, email, phone, color, code, number detection via NSDataDetector and regex heuristics; used for filtering and search
- **Custom Shortcuts** - Rebind all hotkeys in Settings > Shortcuts (paste, pin, star, lock, edit, tag, delete, create folder, toggle sidebar, toggle preview, cycle scopes, quick-paste); conflict detection; live re-registration
- **Permissions Management** - Dedicated Permissions tab and menu item; status display for Accessibility permission; request button; link to System Settings; first-launch onboarding replaces blind prompt
- **iCloud Drive Sync** - Optional sync across devices via `~/Library/Mobile Documents/com~apple~CloudDocs`; per-device snapshots prevent conflicts; tombstones track deletes; content deduplication by hash; disable sync to keep data local-only; large files (>50 MB) stay local with reference badge
- **Configurable History Limit** - Presets: 1,000 / 5,000 / 10,000 / Unlimited; default 10,000; locked and pinned items never evicted
- **Font Scaling** - Adjustable text size for list and preview pane; sliders in Settings > Appearance; fonts routed through semantic helpers
- **Inline Text Editing** - Edit text/code snippets directly (up to 5,000 chars); changes auto-save and sync to clipboard; global shortcuts bypass while editing
- **Search Enhancements** - Full-text search matches: OCR text, tags, source app, file names, image content; multi-word AND logic; search persists 90s after window close

### Changed

- **App Rename** - Rebranded from Buffer to Klip; bundle ID changed from `com.samirpatil.Buffer` to `com.fxreza.klip`; data directory moved to `~/Library/Application Support/Klip`; automatic one-time migration from Buffer on first launch, with Buffer's data left untouched
- **Default Paste Behavior** - Default paste now keeps formatting (RTF/HTML) instead of always stripping to plain text; "Always paste as plain text" setting available for users who prefer the old behavior
- **Updater** - Auto-updater redirected from upstream Buffer releases to this fork's GitHub releases (tag format: `klip-vX.Y.Z`)
- **History Window** - Now a floating NSPanel with material design instead of standard window; sidebar added for navigation; content filters added
- **Settings** - Unified into single `SettingsManager` source of truth; tabbed layout (General, Appearance, History, Shortcuts, Files, Sync, Permissions)

### Fixed

- Invalid sort predicate in history list (was causing undefined sort order); replaced with stable pinned-first partition
- Decode failures silently discard history; now renamed to `history.corrupt-<date>.json` for recovery
- Settings panel had multiple sources of truth; consolidated into `SettingsManager`
<!-- 5Cb -->
- **Keyboard shortcuts hijacked other windows (5A-01)** - the history panel's key monitor is process-wide, so Return in a Save panel, in the Clear History alert or in an update alert was swallowed and pasted the clip into the frontmost app instead, and ⌘C/⌘S/⌘E/⌘L/⌘P/⌘B/⌘1-9 fired while Settings, Permissions or Onboarding had focus; the monitor now only acts on events belonging to the history panel while it is the key window
- **Copying a very large clip froze the app (5A-04)** - a 15 MB text clip blocked the UI for 5 seconds at capture; classification is capped at the first 64 KB, the `SELECT…FROM` regex is gone, and classification plus the text/RTF/flavors disk writes now run off the main thread (main-thread block: 5,001 ms → 3.7 ms), with capture cadence and duplicate suppression unchanged
- Image thumbnails were drawn with `lockFocus` off the main thread (5A-07) - now rendered into a bitmap context, which is thread-safe
- Image thumbnails were re-read and re-rendered from disk on every scroll (5A-10) - now cached per item and size, and evicted when a clip is deleted
- Updater could leave you with no app at all (5A-11) - the installer staged the new build beside the old one, swaps them, and restores the old app if any step fails
- Updater accepted any signed build at the download URL (5A-12) - an update must now carry Klip's bundle identifier and the same signing identity as the running app, or it is refused with an explanation; the download's size is sanity-checked too
- Hovering the list rebuilt the whole 10,000-row array (5A-14), and every keystroke re-folded every clip's searchable text (5A-15, worst case 35.6 ms → 7.4 ms per keystroke at 10,000 clips)
- Right-clicking a row changed the selection from inside a view update (5A-19) - now handled on the mouse-down
- A multi-item paste containing images or files could be captured back as a new clip (5A-21)
- "Save to Disk" deleted the file already at the chosen path before copying, losing it if the copy failed (5A-23)
- ⇧↑ / ⇧↓ could crash on a stale selection index (5A-22); the index is now clamped whenever the list changes
- Updater and build scripts quoted paths incorrectly (5A-25, 5A-26); a QuickLook preview could crash on a failed initialiser (5A-32)
- Row menu entries that act on the whole selection now say so ("Lock 10 Clips"), instead of a single-clip label doing a ten-clip action (5A-30)
<!-- /5Cb -->

### Internal

- **Architecture** - Split 1,914-line `Views/HistoryWindow.swift` into modular `Views/History/*` files; introduced `FilterState` struct eliminating 5x duplicated filter logic
- **Model Enhancement** - Added `isLocked`, `folderID`, `kind: ContentKind`, `FileAttachment` to `ClipboardItem`; added `Folder` model; v2 schema with migration support
- **Atomic Storage** - History/folders/settings writes now atomic (`.atomic` flag) and debounced (300ms); survives interruptions
- **Build System** - Canonical build via `scripts/build_local.sh` (ad-hoc) and `build_dmg.sh` (notarized if .env present); Xcode project synced automatically via `scripts/sync_xcodeproj.py`; test suite with swiftc-based runner (no XCTest dependency)
- **Test Coverage** - 215+ tests covering models, store, UI state, sync, permissions, shortcuts; offscreen rendering harnesses for view testing

---

## 2.5.0 (upstream)

See https://github.com/samirpatil2000/Buffer for the upstream Buffer changelog.
