# Buffer fork - implementation plan (v3.0.0)

Status: PLANNING - nothing implemented yet. Date: 2026-08-22.
Manager: Fable 5 (this session). Workers: Haiku 4.5 / Sonnet 5 / Opus 5 subagents.
Inputs: `docs/analysis/buffer.md`, `docs/analysis/clipfield.md`, `docs/analysis/pesty.md` (read these before any task).

---

## 0. What was done in this session

| Item | Result |
|---|---|
| Fork vs download | **Cloned with full git history** into the project root; remote `upstream` = samirpatil2000/buffer. No GitHub fork created (that would publish a public repo under your account - say the word and I run `gh repo fork --remote`). `git fetch upstream` keeps sync ability. |
| Reference code | `reference/clipfield`, `reference/pesty` (shallow clones, gitignored, both MIT). |
| Structure | `releases/<tag>/` = every version kept; `dist/` = last live build; `docs/analysis`, `docs/plan`. `.gitignore` un-ignores dmg/zip under `releases/` and `dist/`. |
| Baseline build | Compiles with plain `swiftc` on this Mac (Command Line Tools only, **no Xcode.app**), ~18s, warnings only. So all subagents can build-gate their work. |
| Git state | Structure + docs are staged, **not committed** (waiting for your OK). |

---

## 1. Findings that change the plan

1. **Buffer stores history as one `history.json`** rewritten on every change (non-atomic, silent discard on decode error). Max history is a hard 1,000 ("unlimited" is a lie). 10,000 items is fine with JSON once writes are atomic/debounced; true unlimited works too but will slow past roughly 30-50k items. SQLite is not needed for v3.0.
2. **`Views/HistoryWindow.swift` is a 1,914-line monolith** with the filter/selection logic copy-pasted 5 times. It must be split before two agents can work in parallel.
3. **Clipfield needs macOS 14 + SwiftData**; Buffer targets macOS 13. We port Clipfield's UI code and design tokens, not its storage. Clipfield's single-click pastes - we keep Buffer's click-only-selects behavior.
4. **Clipfield has no folder rename and no drag-into-folder**; both get written new.
5. **Pesty's CloudKit sync only exists in its Mac App Store build** (paid Apple Developer account, sandbox, provisioning profile). Its direct-download build uses **iCloud Drive file sync** (zero entitlements) - that one matches Buffer's build exactly and is the recommended path.
6. **Buffer captures plain text only** (no RTF/HTML). "Paste as plain text" only means something if we start capturing rich text - this changes default paste behavior (see D5).
7. **UpdateService auto-updates from upstream GitHub releases** and replaces `/Applications/Buffer.app`. Left as-is, upstream's next release would silently overwrite your build (see D2).
8. Two sources of truth for settings, no row context menu, no file-type items, ~60 hardcoded font sizes, only Accessibility permission handled (prompted blindly at every launch).

---

## 2. Decisions I need from you (D1-D7)

Phase 0 and Phase 1 tasks 1A/1C can start without these. Everything else waits.

| # | Question | My recommendation |
|---|---|---|
| **D1** | Commit the baseline + docs now? Create a GitHub fork `fxreza/buffer` and push? | Commit yes. Fork: your call - useful for backup and for the updater (D2). |
| **D2** | App identity: keep bundle id `com.samirpatil.Buffer` and the upstream updater? | **Change** bundle id (e.g. `com.fxreza.buffer`) and point `UpdateService` at your own repo releases (or disable it). Otherwise upstream auto-update wipes the fork. Display name can stay "Buffer". |
| **D3** | History limit | Setting with presets 1,000 / 5,000 / 10,000 / Unlimited. **Default 10,000**, Unlimited available. Keep JSON, make writes atomic + debounced. Locked/starred/pinned/tagged/foldered items never count as evictable. |
| **D4** | Folder semantics: does moving a clip into a folder remove it from the main history list, or does it stay visible there too (Clipfield style)? | **Stays visible in "All"**, appears in its folder, locked by default. History stays a complete timeline; nothing "disappears". Alternative (true move) is the same amount of work - just say which. |
| **D5** | Start capturing rich text (RTF/HTML + raw pasteboard flavors) so "Paste as Plain Text" is meaningful? This changes today's behavior: default paste would keep formatting. | **Yes**, plus a setting "Always paste as plain text" (off by default) so you can get today's behavior back with one toggle. Needs your explicit approval because it changes an existing behavior. |
| **D6** | File clips: copy the file into Buffer's storage (survives the original being moved/deleted, costs disk) or only reference the path? | **Copy if <= 50 MB per file**, otherwise store a reference + security bookmark and show a "reference" badge. Cap adjustable in Settings. |
| **D7** | iCloud: iCloud Drive file sync (no developer account needed, works with current build) or CloudKit (needs paid Apple Developer Program, sandboxed signed build, 5-8 extra days)? Do you have an Apple Developer Program membership? | **iCloud Drive file sync** (Pesty's direct-download approach, improved with per-device files + tombstones). CloudKit only if you already pay for the program and want push-speed sync. |

### Decisions log (answered 2026-08-22, all phases approved to run unattended)

| # | Decision |
|---|---|
| D1 | Baseline committed (`baseline-v2.5.0`), fork created and renamed: **https://github.com/fxreza/Klip** (`origin`), pushed at each phase tag. Commits use the GitHub noreply identity (email privacy). |
| D2 | **App renamed to "Klip"**: bundle id `com.fxreza.klip`, data dir `~/Library/Application Support/Klip` (history + defaults copied from Buffer on first launch, originals untouched), updater points at `fxreza/Klip` releases, and I **publish GitHub release `klip-v3.0.0`** with the DMGs at the end. Swift type names and notification names stay as-is internally. |
| D3 | History limit presets 1,000 / 5,000 / 10,000 / Unlimited, default 10,000. |
| D4 | Clips moved into a folder stay visible in "All". |
| D5 | Rich-text capture approved; default paste keeps formatting; explicit Plain option; setting "Always paste as plain text". |
| D6 | File clips copied into storage up to a cap chosen from 1 / 5 / 10 / 50 / 100 / 500 MB / Unlimited or a custom value; above the cap = reference + bookmark. Default 50 MB. |
| D7 | iCloud Drive file sync. No CloudKit. |
| Signing | Builds signed with the local self-signed "QTranslate Dev" identity (stable identity so Accessibility grant survives rebuilds); ad-hoc fallback. |
| Install | At the end: back up `~/Library/Application Support/Buffer` to `releases/backup-<date>/`, quit upstream Buffer, **move /Applications/Buffer.app to Trash**, install `/Applications/Klip.app`, launch. User grants Accessibility once on return. |
| Testing | Test builds always run with `KLIP_DATA_DIR` pointing at a scratch dir and `KLIP_DEBUG=1` (Darwin-notification hooks to show/hide the window) so the user's live data and hotkey are never touched. |

Decided by me (say if you disagree): min macOS stays 13.0; window becomes Clipfield-style borderless material panel (still resizable, size persisted); pinned keeps float-to-top; Favorites = existing bookmark/star flag; lock on move-into-folder, lock state unchanged on move-out; no third-party packages; Xcode project kept in sync but `swiftc` script is the canonical build (no Xcode here).

---

## 3. Target architecture (after v3.0.0)

```
Models/      ClipboardItem (+isLocked, folderID, kind, file fields, rich flavors)   Folder   ContentKind   KeyBinding
Services/    ClipboardStore (history.json + folders.json + images/ texts/ files/ flavors/, atomic+debounced, schemaVersion)
             ClipboardWatcher (text | rich | image | files)   PasteController (rich/plain/files)   ContentDetector
             SettingsManager (single source of truth)   ShortcutManager (table-driven)   HotkeyManager   PermissionsState
             CloudDriveSync (Phase 4)   OCRService   UpdateService (re-pointed)
Views/       Theme.swift  Appearance.swift  FontScale.swift
             History/   HistoryPanel+Controller, HistoryContentView (shell), Sidebar, SearchBar, FilterChipBar,
                        ClipList, ClipRow, PreviewPane (+FilePreview), ActionBar, GlobalKeyMonitor, prompts (NewFolder, Rename, DeleteFolder)
             Settings/  SettingsView tabs: General, Appearance, History, Shortcuts, Files, Sync, Permissions
             Permissions/ OnboardingView
scripts/     build_local.sh (ad-hoc .app, no .env)   run_tests.sh (swiftc test runner)   sync_xcodeproj.py   release.sh
```

Sidebar: **All** - **Favorites** (starred) - FOLDERS (user folders, counts) - "+ New Folder". Chip row under search: All / Text / Link / Image / File / Color / Code / Email / Phone (plus the existing tag filter). Everything in the Clipfield look (regularMaterial panel, 18pt radius, accent gradient selection with matchedGeometryEffect, 38x38 badges, preview pane with metadata footer).

---

## 4. Model assignment rubric

| Model | Use for | Typical cost / task |
|---|---|---|
| **Haiku 4.5** | Mechanical, fully specified, low ambiguity: scripts, docs, sweeps of literals, checksums, attribution, pbxproj bookkeeping when given exact instructions | 30-100k tokens |
| **Sonnet 5** | Feature work with a clear spec touching 1-5 files, porting code from reference/, settings UI, tests, bug fixes from a review list | 150-450k |
| **Opus 5** | Architecture and refactors, the UI shell rewrite, drag-and-drop, sync/merge logic, adversarial reviews | 400k-1.5M |
| **Fable 5** (me) | Manager: writing task briefs, merging worktrees, build/smoke gates, final review of risky merges, talking to you | - |

Rough total for v3.0.0: **6-9M tokens** (Phase 2 and Phase 4 dominate). Shrink by skipping Phase 4 (sync) or the file-preview nice-to-have.

---

## 5. Phases and tasks

Legend: `[P]` runs in parallel with siblings, `[S]` serial. Every task: runs in its own git worktree, must pass `scripts/build_local.sh` with zero errors and no new warnings, must not edit files outside its "Owns" list, returns a summary + `git diff --stat`. I merge, rebuild, smoke-test, then start the next wave.

### Phase 0 - Baseline and tooling (serial, ~1 hour, blocks everything)

| ID | Model | Task | Owns | Done when |
|---|---|---|---|---|
| 0.1 | Fable | Commit baseline (structure + docs), tag `baseline-v2.5.0`, create branch `main` as fork dev branch (needs D1) | git | tag exists |
| 0.2 | Haiku | `scripts/build_local.sh`: arm64 (+ optional x86_64) ad-hoc-signed `.app` into `build/`, no `.env` needed, same bundle layout as `build_dmg.sh` (Info.plist, icon, entitlements), `--dist` flag copies to `dist/`; `scripts/run_app.sh` kills+relaunches it | `scripts/` | `./scripts/build_local.sh && open build/Buffer.app` works |
| 0.3 | Sonnet | `scripts/run_tests.sh`: compiles `Models/ Services/` + `Tests/*.swift` with a tiny assertion runner (no XCTest - no Xcode here), ports the one existing test; CI-style exit code | `scripts/`, `Tests/` | passes on baseline |
| 0.4 | Haiku | Apply D2: bundle id + `UpdateService` repo constant (or disable), `build_dmg.sh`/`build_local.sh`/pbxproj/Info.plist consistent | `Services/UpdateService.swift`, plist, scripts, pbxproj | grep shows no `samirpatil` in runtime code paths |
| 0.5 | Haiku | Build baseline into `releases/v2.5.0-upstream/` (ad-hoc) + `checksums.txt` + note that it is unmodified upstream | `releases/` | files present |

### Phase 1 - Foundation (3 parallel worktrees, then I integrate)

| ID | Model | Task | Owns | Done when |
|---|---|---|---|---|
| 1A `[P]` | **Opus** | **Split `Views/HistoryWindow.swift`** into `Views/History/{HistoryPanel,HistoryWindowController,HistoryContentView,DetailPane,ActionBar,SearchBar,TagSection,GlobalKeyMonitor,RelativeTimestampView}.swift`. Introduce one `FilterState` struct + one `applyFilters()` replacing the 5 duplicated recompute/selection-reset blocks. Fix the invalid sort predicate. Zero behavior change. | `Views/History/*`, `Views/HistoryWindow.swift` (deleted) | build passes; manual checklist (section 7) all green |
| 1B `[P]` | **Opus** | **Model + store foundation**: `schemaVersion` in `history.json` wrapper (`{version, items}`) with migration from bare array; `isLocked`, `folderID`, `kind: ContentKind?` fields; `ClipboardItemType.file` + `FileAttachment {originalName, storedPath, referencePath, bookmark, uti, byteSize}`; `Folder {id, name, createdAt, sortIndex}` + `folders.json`; store CRUD for folders (`createFolder/renameFolder/deleteFolder(mode:)/moveItems(to:)`), `isProtected` extraction, lock guards in `delete/delete([])/clear/evict` returning `(deleted, skippedLocked)`; history limit as `Int` (0 = unlimited) with presets; atomic writes (`.atomic`) + 300ms debounced save; on decode failure rename the bad file to `history.corrupt-<date>.json` instead of discarding. Tests in `Tests/`. | `Models/*`, `Services/ClipboardStore.swift`, `Services/SettingsManager.swift` (limit only), `Tests/` | tests pass; old `history.json` loads unchanged |
| 1C `[P]` | Sonnet | **Settings unification + design tokens**: delete `SettingsViewModel`, make `SettingsManager` an `ObservableObject` single source of truth; port `Theme.swift` + `Appearance.swift` from Clipfield (radii, accentGradient, springs, kind tints, `Color(hexString:)`, AccentTheme, AppColorScheme); add `FontScale` (`@Environment` scale factor + `Font.buffer(.row/.title/.caption/.preview)` helpers) and a `fontScale` + `previewFontScale` setting with Appearance tab UI (no sweep yet); delete dead code (`Views/SearchField.swift`, `moveToTop`, `truncatedText`, `simulatePasteWithDelay`, unused `ClipboardListView` params). | `Views/SettingsView.swift`, `Services/SettingsManager.swift` (non-limit keys), `Views/Theme.swift`, `Views/Appearance.swift`, `Views/FontScale.swift`, dead files | build passes; every existing setting still round-trips |
| 1Z `[S]` | Fable | Merge 1A+1B+1C, resolve conflicts (1B and 1C both touch `SettingsManager` - pre-agreed split by key), rebuild, smoke test, tag `v3.0.0-alpha1` | - | app launches, history intact |

### Phase 2 - Clipfield UI shell (one Opus agent, serial, the big one)

| ID | Model | Task | Owns | Done when |
|---|---|---|---|---|
| 2A `[S]` | **Opus** | Rebuild the history window in the Clipfield look using the split views from 1A and the model from 1B. Spec: borderless `NSPanel` (`.borderless, .resizable`, floating, clear bg, `canBecomeKey`), content `.regularMaterial` + 18pt radius + white 12% hairline, centered on the mouse screen 8% above center, size persisted (min 560x380). Layout: **Sidebar** (All / Favorites / FOLDERS list with counts / New Folder, resizable 120-320, collapsible, accent-gradient selection with matchedGeometryEffect) | **SearchBar** (existing search + tag pill, Clipfield styling) | **FilterChipBar** (All, Text, Link, Image, File, Color, Code, Email, Phone - wired to `ContentKind`, detection itself is 3C; chips filter on whatever `kind` is present) | **ClipList/ClipRow** (38x38 badge: thumbnail / color swatch / kind icon with tint, title 2 lines, subtitle source app + relative time, tag chips, badges for pin/star/lock, hover 6%, selection gradient + glow) | **PreviewPane** (kind header, image / color / text body, keep OCR button, edit mode, chunked large text, multi-selection summary; metadata footer: Copied, From, Size, Folder, Tags) | **ActionBar** (nav, legend, PasteButton). All fonts through `FontScale`. **Preserve**: click = select only, double-click = copy+close, Enter/PasteButton = paste, ⌘-click/⇧-click multi-select, all hotkeys, tag flow, edit, pin, star, save image, OCR, search persistence, pause capture, hide icon. Scope filtering: All / Favorites (`isBookmarked`) / folder (`folderID`). Lock badge shown; lock toggling UI comes in 3A. | `Views/History/*`, `Views/ClipboardListView.swift`, `Views/ClipboardItemRow.swift`, `Views/PasteButton.swift`, `Views/TagChip.swift` | checklist (section 7) all green + screenshots side by side with Clipfield |
| 2B `[S]` | Sonnet | Refute-review of 2A against the section-7 checklist (reads code, runs app, tries each behavior). Produces a bug list; 2A agent fixes. | read-only | zero regressions |
| 2Z | Fable | Merge, tag `v3.0.0-alpha2` | | |

### Phase 3 - Features (parallel worktrees; file ownership prevents conflicts)

| ID | Model | Task | Owns | Done when |
|---|---|---|---|---|
| 3A `[P]` | Sonnet | **Lock / protect**: toggle in row context menu + preview pane button + ⌘L; lock badge; delete/⌘⌫/multi-delete/Clear History skip locked and show "N locked items skipped - unlock first" toast; items moved into a folder get `isLocked = true`; Settings > History explains the rule. | `Services/ClipboardStore.swift` (lock funcs), `Views/History/DetailPane.swift` (lock button), `Views/History/LockToast.swift`, `Views/StatusBarController.swift` (clear alert copy) | can't delete a locked clip by any path; unlock then delete works |
| 3B `[P]` | **Opus** | **Folders UX + drag and drop**: New Folder inline prompt (no NSAlert - it would dismiss the panel); rename via double-click in sidebar, context menu, or F2-style shortcut; delete: empty -> immediate; non-empty -> inline confirm sheet with "Move N clips to All" or "Delete N clips (M locked)" requiring a second explicit confirm for locked; context menu "Move to Folder >" submenu incl. multi-select; **drag rows onto sidebar folders** (`onDrag` NSItemProvider carrying UUIDs, `onDrop` on sidebar rows with highlight; make `ClickModifierDetector` overlay forward drags); text, image and file items all allowed; folder counts live. | `Views/History/Sidebar.swift`, `Views/History/FolderPrompts.swift`, `Views/History/ClipRow.swift` (drag only), `Views/History/ClickDetector.swift`, `Services/ClipboardStore.swift` (folder funcs only) | create/rename/delete/move/drag all work, locked clips survive a folder delete unless explicitly confirmed |
| 3C `[P]` | Sonnet | **Content kind detection + chip filtering + search upgrade**: `Services/ContentDetector.swift` ported from Clipfield `SmartTagger` (link, email, phone, color, code, number; NSDataDetector + regex), run at capture and lazily backfilled for existing items; chips combine with scope + tag + query; search now also matches `ocrText`, tags, source app, file names and images with OCR text (additive only). | `Services/ContentDetector.swift`, `Services/ClipboardWatcher.swift` (kind assignment), `Views/History/FilterChipBar.swift`, `Views/History/FilterState.swift` | each chip isolates the right items; old searches still match |
| 3D `[P]` | Sonnet | **Row context menu + plain-text copy/paste** (needs D5): right-click menu on rows: Paste, Paste as Plain Text, Copy, Copy as Plain Text, Edit, Pin, Star, Lock, Move to Folder (hook from 3B), Add Tag, Save to Disk, Reveal in Finder (files), Open Link, Delete. Capture RTF/HTML + raw flavors (port Clipfield `PasteboardReader`/`PasteboardFlavors`, store as `flavors/<uuid>.plist`, 16 MB cap); `PasteController.paste(item, plain:)`, `pasteMultiple(plain:)`, `copy(plain:)`; ⌥↩ / ⇧⌘↩ = plain; PasteButton becomes a split button; setting "Always paste as plain text". | `Services/PasteController.swift`, `Services/ClipboardWatcher.swift` (rich capture), `Services/ClipboardStore.swift` (flavors files), `Views/History/RowContextMenu.swift`, `Views/PasteButton.swift` | rich paste keeps formatting in Pages/Mail; plain paste strips it; old items still paste |
| 3E `[P]` | Sonnet | **Custom shortcuts**: `ShortcutAction` enum (paste, pastePlain, copy, copyPlain, pin, star, lock, edit, tag, saveToDisk, delete, newFolder, renameFolder, moveToFolder, toggleSidebar, togglePreview, nextScope/prevScope, quickPaste1-9); `KeyBinding {keyCode, modifiers}` per action in UserDefaults with defaults = today's keys; `GlobalKeyMonitor` becomes table-driven; Settings > Shortcuts tab with one recorder per action (port Clipfield `HotkeyRecorder`), conflict detection, Reset; global hotkey row reuses it; legend, `.help()` strings and status-bar label read bindings. | `Models/KeyBinding.swift`, `Services/ShortcutManager.swift`, `Views/History/GlobalKeyMonitor.swift`, `Views/Settings/ShortcutsTab.swift`, `Views/Settings/HotkeyRecorder.swift`, `Views/History/ActionBar.swift` (legend) | rebinding ⌘P to ⌘⇧P works immediately; no duplicates allowed |
| 3F `[P]` | Sonnet (Opus review) | **File clips** (needs D6): capture file URLs of any type and count -> `.file` items (copy into `files/<uuid>/<name>` under cap, else reference + bookmark); icon via `NSWorkspace.icon(forFile:)`; **thumbnails via `QLThumbnailGenerator`** (QuickLookThumbnailing - gives pdf/csv/txt/xlsx/py previews for free) with fallback icon; preview pane uses `QLPreviewView` (Quartz) for files, text files show content; paste writes file URLs (Finder copies, apps attach/insert); "Save to Disk" for single and multi (extends existing image save + Download All); size and count in metadata; eviction deletes stored copies. | `Services/ClipboardWatcher.swift` (file branch), `Services/ClipboardStore.swift` (files dir), `Services/PasteController.swift` (file paste/save), `Views/History/FilePreview.swift`, `Views/History/ClipRow.swift` (file badge) | copy a .py/.xlsx/.pdf in Finder -> shows with thumbnail -> paste into Finder creates the file -> Save to Disk works |
| 3G `[P]` | Sonnet | **Permissions + onboarding**: `PermissionsState` (port Clipfield, 1s poll of `AXIsProcessTrusted`); status-bar menu "Permissions..." and Settings > Permissions tab listing: Accessibility (status, Request, Open System Settings, why), Launch at Login, iCloud Drive availability (hook for Phase 4), Notifications not used; first-run `OnboardingView` replaces the blind launch prompt; in-app hint when a paste fails for lack of AX. | `Services/PermissionsState.swift`, `Views/Permissions/*`, `Views/StatusBarController.swift` (menu item), `AppDelegate.swift` (launch flow) | denied AX shows guidance instead of silently failing |
| 3H `[S]` after 2A | Haiku | **Font-size sweep**: grep every remaining `.font(.system(size:` / `NSFont.systemFont(ofSize:` in `Views/` and route through `FontScale`; verify row height, badge size, truncation scale with it; Appearance tab has "List text size" and "Preview text size" sliders (from 1C). | `Views/**` font literals only | zero raw size literals left in list/preview; slider visibly resizes both |
| 3Z | Fable | Merge order: 3A -> 3C -> 3E -> 3D -> 3B -> 3F -> 3G -> 3H (least to most conflict-prone), rebuild + smoke each; tag `v3.0.0-beta1` | | |

Conflict hot-spots and how they are handled: `ClipboardStore.swift` is touched by 3A/3B/3D/3F in disjoint function groups (lock / folder / flavors / files) - each brief names its allowed functions; `ClipboardWatcher.swift` by 3C/3D/3F (kind / rich / file branches) - the brief for 3D and 3F gives the exact insertion points; `ClipRow.swift` by 3B (drag) and 3F (badge). Anything else overlapping is a merge I do by hand.

### Phase 4 - iCloud sync (needs D7; after 3B so folders sync too)

| ID | Model | Task | Owns | Done when |
|---|---|---|---|---|
| 4A `[S]` | **Opus** | **iCloud Drive file sync** (Pesty approach, hardened): Settings > Sync toggle (disabled with reason if `~/Library/Mobile Documents/com~apple~CloudDocs` is missing); on enable migrate store to `.../CloudDocs/Buffer/`; **per-device snapshot files** `history-<deviceID>.json` / `folders-<deviceID>.json` merged on read (content-hash dedupe, newest wins for flags, union for tags) to avoid two Macs clobbering one file; `tombstones.json` so deletes don't resurrect; images/texts/files/flavors dirs shared by uuid; `DispatchSource` + `NSMetadataQuery` watcher; coordinated writes (`NSFileCoordinator`); size cap for synced files (default 50 MB, larger stays local-only with badge); status line in Settings and Permissions. | `Services/CloudDriveSync.swift`, `Services/ClipboardStore.swift` (storage root + merge hooks), `Views/Settings/SyncTab.swift` | two Macs (or two user accounts) converge; deleting on one deletes on the other; locks/folders survive |
| 4B `[S]` | Sonnet | Refute-review of 4A: conflict scenarios, offline edits, corrupt remote file, disabling sync (migrate back), iCloud signed out. | read-only | bug list -> 4A fixes |
| (alt) | Opus | CloudKit port from Pesty - only if D7 says so and a provisioning profile exists. ~5-8 days. | | |

### Phase 5 - QA, docs, release

| ID | Model | Task | Owns | Done when |
|---|---|---|---|---|
| 5A `[P]` | **Opus** | Adversarial review of full diff `baseline-v2.5.0..HEAD`: every row of section 6 and 7, crash hunting (sort predicates, main.sync, off-main drawing, file handles), performance with 10k items (generate fixture). | read-only | findings list |
| 5B `[P]` | Sonnet | `scripts/sync_xcodeproj.py`: adds any `.swift` not in `project.pbxproj` (file ref + build file + group + sources phase), update test target; run it. | `scripts/`, `Buffer.xcodeproj/` | pbxproj lists every file |
| 5C `[S]` | Sonnet | Fix 5A findings | as needed | 5A re-run clean |
| 5D `[P]` | Haiku | Docs: README fork section + feature list, `CHANGELOG.md`, `ATTRIBUTION.md` (Clipfield + Pesty MIT notices), `RELEASE.md` update for `releases/` + `dist/`, `release_notes.md`, version bump 3.0.0 / build 8, SECURITY.md wording for sync. | docs, plist | - |
| 5E `[S]` | Fable | `scripts/release.sh`: build (signed+notarized if `.env` exists, else ad-hoc), copy to `releases/v3.0.0/` and `dist/`, checksums, `git tag buffer-v3.0.0`; optional `gh release create` on your fork. | scripts, releases, dist | `dist/` has the live build |

---

## 6. Requested-feature traceability

| Your request | Task(s) |
|---|---|
| Same UI design and colors as Clipfield | 1C (tokens), 2A, 3H |
| Folders/collections in a left sidebar | 1B, 2A, 3B |
| Text, images, files inside folders | 1B, 3B, 3F |
| Lock/protect; folder clips locked by default; locked clips immune to cleanup / select-delete / right-click / shortcut until unlocked | 1B, 3A, 3B |
| Keep favorites + real Favorites section | 2A (sidebar scope on `isBookmarked`) |
| One click must not paste or close | 2A preserve list, 2B review |
| Filter chips under search (image, text, url, ...) | 2A, 3C |
| Save images to disk + same for any file type | 3F |
| Adjustable text/font size for list and preview | 1C, 3H |
| History limit 5,000 / 10,000 / unlimited | 1B (D3) |
| Keep multi-select, multi-paste, edit, tags | 1A, 2A, 2B |
| Explicit Copy/Paste as Plain Text | 3D (D5) |
| Image thumbnails; previews for pdf/csv/txt if easy | 2A, 3F (QuickLook - low risk, built in) |
| Move/drag clips into folders | 3B |
| Rename folders | 3B |
| Delete empty folders; non-empty needs explicit confirm, protects locked | 3B |
| Custom shortcuts in settings | 3E |
| Permissions request menu | 3G |
| iCloud sync if not too complicated | 4A (D7) |
| Keep all current functions / ask before changing one | section 7 checklist at every merge; D2 and D5 are the only behavior changes and wait for your approval |

---

## 7. Existing-feature preservation checklist (run at 1Z, 2B, 3Z, 5A)

1. Global hotkey ⇧⌘V toggles the panel; hotkey change in Settings takes effect immediately.
2. Copying text / image in any app appears at the top within 0.5s; duplicates dedupe.
3. Single click selects only; window stays open. Double-click copies + closes. Enter pastes into the previous app. Paste button pastes.
4. ⌘-click toggles, ⇧-click / ⇧↑↓ extend; multi-select summary shows counts; Enter pastes all (texts joined, images as files); Download All for images.
5. ⌘P pin (floats to top, header), ⌘B star, ⌘E edit (<= 5000 chars, saves on exit and updates clipboard), ⌘T tag + Tab completion + `#tag` search + chip filter + ⌫ clears filter, ⌘S save image, OCR button + copy.
6. Search debounced, persists 90s after close, selection restored.
7. Large text (> 50 KB) stored as file, chunked preview, pastes in full.
8. Settings: hotkey, history limit with downgrade warning, prereleases, hide menu bar icon, launch at login - all round-trip.
9. Status bar: left-click toggles, right-click menu (Settings, Check for Updates, Pause/Resume, Clear History, Quit).
10. Existing `history.json` from v2.5.0 loads without loss.
11. Esc closes (after exiting edit / tag input); clicking outside closes.
12. Update check does not point at upstream (after D2).

---

## 8. Execution protocol (how I will run it)

1. You answer D1-D7 (or say "go with your recommendations").
2. Phase 0: I run 0.1 myself, then 0.2-0.5 as background agents (Haiku/Sonnet), merge.
3. Phase 1: three agents at once (`isolation: worktree`), each brief = its row above + `docs/analysis/*` pointers + ownership list + build/test gate + "return summary and diff stat, do not commit to main".
4. I merge each worktree, run `scripts/build_local.sh`, launch the app and walk the checklist (screenshots via computer-use when useful), tag.
5. Phase 2 runs one Opus agent for as long as it needs; 2B reviews; repeat until green.
6. Phase 3 wave of 7 agents; merge in the stated order; Phase 4; Phase 5; release into `releases/v3.0.0/` + `dist/`.
7. I report after every phase with what changed, what is open, and ask before any behavior change not already approved.
