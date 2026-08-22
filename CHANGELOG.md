# Changelog

All notable changes to Klip are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## 3.0.2 (2026-08-22)

### Added

- **Tags chip** - A `Tags` chip in the filter row narrows the list to clips carrying at least one tag. Activating it shows every tag (most-used first) in a bar under the chips; clicking one narrows further to that tag, and clearing the tag filter (⌫ on an empty search, or the tag pill's ×) drops back to "all tagged clips" with the chip still active. Typing `#tag` in search still works exactly as before, and now lights the Tags chip too.
- **`# tags` legend hint** - The action bar's shortcut legend now includes `# tags`, pointing at the `#tag` search syntax and the new Tags chip.

### Changed

- **Shortcut legend wraps instead of dropping shortcuts** - At the default window width (sidebar and preview both open), the full legend no longer collapses straight to "navigate / paste" - it now wraps onto up to two compact rows, so `⌥↩ paste plain` and `# tags` (and everything else) stay visible. Only drops to the shorter tier if the full set still doesn't fit in two rows.
- **Settings footer trimmed** - The "Designed to disappear" tagline and the Star on GitHub / Report an Issue links are gone from Settings; only the version line remains.

---

## 3.0.1 (2026-08-22)

Fixes from the first live test of 3.0.0.

### Fixed

- **Crash when previewing a file clip** - Selecting a `.file` clip could abort the app. The preview pane embedded a live `QLPreviewView`, and setting its preview item from inside a SwiftUI layout pass trips a QuickLook assertion that calls `abort()` (three crash reports on 3.0.0). QuickLook *UI* classes are gone from the app entirely; the pane now renders a static QuickLook thumbnail instead, generated off the main thread and cached like the row badge. A build-time check in `scripts/gate.sh` fails if `QLPreviewView` ever reappears in the binary.
- **Keyboard navigation without scrolling** - Arrow keys could move the highlight off screen. Every selection change now scrolls the list, synchronously and again on the next run loop, centring the row only when it is actually off screen so it never fights manual scrolling. A filter or delete that pushes the selection out of view re-scrolls too.
- **OCR copy button did nothing** - The copy icon beside text extracted from an image wrote to the clipboard with no confirmation, and its hit area was the bare 12 pt glyph, so a miss and a failure looked identical. It now has a real hit target, goes through the same copy path as every other clip (so the watcher does not re-capture it), and confirms with an "OCR text copied" toast.
- **Selection highlight blink** - Key-driven selection moves apply the highlight without the spring animation, which restarted on every row while an arrow key repeated. Mouse clicks still animate.

### Changed

- **Favorite is ⌘F** - The favorite shortcut moved from ⌘B to ⌘F. Nothing else uses ⌘F (the search field is focused automatically), and it is easier to reach. Anyone who already rebound the action keeps their own binding.
- **"Star" is now "Favorite"** - The action is called Favorite / Unfavorite everywhere it is shown: the shortcut legend, the row context menu, the preview pane's button, Settings > Shortcuts and the Settings and Clear History wording. The sidebar section is still "Favorites".
- **Preview pane is full height** - The preview is now a panel beside the list, like the sidebar, rather than a box between the filter chips and the action bar. All resizing and persistence behaviour is unchanged.
- **Paste button removed** - The blue Paste button and its split menu are gone from the action bar. ↩ pastes and ⌥↩ pastes plain, both now shown in the legend; "Always paste as plain text" stays in Settings > General and the plain/rich alternate stays in the row context menu.
- **Scope cycling removed** - ⌘[ / ⌘] no longer cycle sidebar scopes, and the two actions are gone from Settings > Shortcuts. Click the sidebar instead. A binding stored for either action before 3.0.1 is ignored without disturbing the rest of your shortcuts.
- **File preview detail** - The file card now shows the file's kind alongside its name and size, and offers Open as well as Reveal in Finder.

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
- **Copying froze the app when the history was over its limit** (5A-02) - eviction ids are now batched into a single `sync-ignore.json` write, and a history that is already over the limit is trimmed once at launch instead of inside the next copy. One `add()` on a 10,000-item store over cap: 162 s → 1.3 ms
- **Every copy rewrote `sync-ignore.json` even with sync switched off** (5A-03) - the bookkeeping is skipped entirely when iCloud sync has never been enabled, and debounced when it has. Copy at the cap: 24 ms → 0.4 ms with 9,240 entries, 0.2 ms with sync off
- **One unreadable record lost the entire history** (5A-05) - `history.json` and `folders.json` now decode record by record: bad records are skipped and logged, a copy of the raw file is kept as `history.corrupt-<date>.json`, and every good clip (including every locked one) still loads
- **A delete on another Mac could remove a locked clip** (5A-06 / 4B #3) - a remote tombstone never deletes a locked record; the locked copy is kept and republished, an older tombstone stays inert after an unlock, and a delete made after an unlock still propagates. `applyRemoteMerge` re-checks this locally as well
- **Re-copying the same files left a full second copy on disk** (5A-08) - the capture fingerprint is computed before anything is copied, and unreferenced assets under `images/`, `texts/`, `files/` and `flavors/` are swept once per launch
- **Copying two files with the same name kept only the first** (5A-09) - duplicate basenames are uniquified (`report (2).pdf`) instead of failing the copy and degrading the clip to a reference
- **A fast burst of changes could postpone saving indefinitely** (5A-13) - the 300 ms save debounce now also has a 2 s maximum delay, so an unexpected quit can lose at most the last two seconds
- **Quitting could hang for minutes while iCloud caught up** (5A-16) - the quit-time push is bounded to 3 s in total (attachments that do not fit sync on the next launch) and can no longer race an in-flight sync cycle
- **The same file synced from two Macs stayed two clips forever** (5A-17) - cross-device file dedupe now keys on the file names and size instead of the per-device storage path
- **A merge could delete a file that a surviving clip still pointed at** (5A-18) - assets referenced by a surviving (or content-identical) clip are never deleted while applying a pull
- **Folder changes could stall the window** (5A-24) - `folders.json` is written asynchronously instead of blocking on the history write queue
- Large text whose backing file went missing showed an empty preview pane; it now falls back to the inline preview (5A-28)
- A repeat file capture compared its fingerprint across threads (5A-29); the comparison value is now captured on the main thread
- An oversized pasteboard was fully materialised in memory before being rejected; capture now stops at the 16 MB cap (5A-31)
- **Quitting with iCloud Drive unavailable recreated the cloud folders** (4B #10) - `pushSynchronously()`/`pullSynchronously()` return immediately when sync is off or the container is missing, and `Klip/` is only ever created inside an existing iCloud Drive container
- Cloud snapshots written by a newer version of Klip are now ignored with one clear message instead of being decoded on a best-effort basis (4B #7)
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
- **Test Coverage** - 240+ tests covering models, store, UI state, sync, permissions, shortcuts; offscreen rendering harnesses for view testing

---

## 2.5.0 (upstream)

See https://github.com/samirpatil2000/Buffer for the upstream Buffer changelog.
