# Buffer technical report (this repo, upstream samirpatil2000/buffer v2.5.0, MIT)

Produced 2026-08-22 by an analysis subagent. All paths relative to repo root. Line numbers are for the v2.5.0 baseline (commit d2ca698) and will drift once Phase 1 splits files.

## 1. ARCHITECTURE
### Build: dual and diverging
| | `Buffer.xcodeproj` | `build_dmg.sh` |
|---|---|---|
| Sources | explicit `PBXBuildFile` list (`project.pbxproj:9-31`) | glob `*.swift Models/*.swift Services/*.swift Views/*.swift` |
| Target | `MACOSX_DEPLOYMENT_TARGET = 13.0` | `${DEPLOY_TARGET}` from gitignored `.env` |
| Info.plist | repo `Info.plist` | **generates its own inline plist** (`:64-93`), reads version only |
| Frameworks | Cocoa (+implicit SwiftUI/Vision/Carbon) | `-framework Cocoa -framework SwiftUI -framework Carbon` |
| Arch | native | separate arm64 + x86_64 builds, 2 DMGs/ZIPs |
| Signing | hardened runtime, `Buffer.entitlements`, `DEVELOPMENT_TEAM = N26FZ4GW28` (upstream author) | `codesign --deep --options runtime --entitlements`, notarize + staple (`:106-161`) |
- No `.xcscheme` checked in. No CI workflow (`.github/` only FUNDING.yml). **Every new .swift file must be added to project.pbxproj manually** (build script picks it up automatically).
- Baseline compiles on this Mac with Command Line Tools only: `swiftc -sdk $(xcrun --show-sdk-path --sdk macosx) -target arm64-apple-macosx13.0 -parse-as-library -framework Cocoa -framework SwiftUI -framework Carbon *.swift Models/*.swift Services/*.swift Views/*.swift -o build/Buffer` (~18s, warnings only).
- `Info.plist`: version 2.5.0 build 7, `LSUIElement true`, no usage-description keys. `Buffer.entitlements`: only `app-sandbox = false`.

### Files
| File | Responsibility | Types |
|---|---|---|
| `BufferApp.swift` | `@main`, only a `Settings` scene (effectively unused) | `BufferApp` |
| `AppDelegate.swift` | composition root; owns store, statusBar, watcher, historyWindowController, hotkeyManager; AX prompt at `:26-28`; hotkey toggle `:47-50`; `.bufferHotkeyChanged` -> `reregister` `:52-54`; update check 3s after launch | `AppDelegate` |
| `Models/ClipboardItem.swift` | model + custom Codable | `ClipboardItem`, `ClipboardItemType` (.text/.image) |
| `Services/ClipboardStore.swift` | JSON persistence, eviction, mutations, image/text files | `ClipboardStore: ObservableObject` |
| `Services/ClipboardWatcher.swift` | 0.5s poll, dedup, capture | `ClipboardWatcher` |
| `Services/PasteController.swift` | pasteboard writes, CGEvent ⌘V, save image panel | static `PasteController` |
| `Services/HotkeyManager.swift` | Carbon global hotkey ('BUFF') | `HotkeyManager` |
| `Services/SettingsManager.swift` | UserDefaults prefs singleton | `SettingsManager`, `HistoryLimit`, `HotkeyModifiers`, `keyCodeNames` |
| `Services/OCRService.swift` | Vision text recognition | `OCRService.shared` |
| `Services/UpdateService.swift` | GitHub releases check + self-replace install (**points at upstream repo `samirpatil2000/Buffer`, `:8`**) | `UpdateService.shared` |
| `Views/HistoryWindow.swift` (1,914 lines) | **monolith**: `HistoryPanel` (1-14), `HistoryWindowController` (to 173), `HistoryContentView` (176-1682, ~35 @State), `Array[safe:]` (1684-1688), `GlobalKeyMonitor` (1691-1861), `RelativeTimestampView` (1863-1913) | |
| `Views/ClipboardListView.swift` | list, click routing, pinned header | |
| `Views/ClipboardItemRow.swift` | row + CSS color-swatch parsing (~150 lines) | |
| `Views/ClickDetector.swift` | NSView mouseDown -> modifier flags | `ClickModifierDetector` |
| `Views/PasteButton.swift`, `Views/TagChip.swift` | | |
| `Views/SearchField.swift` | **DEAD CODE** (unused) | |
| `Views/StatusBarController.swift` | menu bar item, right-click menu, Settings window, Clear History alert | |
| `Views/SettingsView.swift` | settings UI, `KeyRecorder`, `SettingsViewModel` (duplicate settings layer `:322-378`) | |

### Data flow
NSPasteboard poll (`ClipboardWatcher.checkClipboard :67`) -> `ClipboardItem.text/.largeText/.image` -> `ClipboardStore.add -> performAdd (:67-103)` (main thread, insert at 0, evict, async save) -> `@Published items` -> `HistoryContentView.onChange(of: store.items) (:544)` -> `computeFilteredItems (:227)` -> `ClipboardListView` -> rows. Enter/PasteButton -> `HistoryWindowController.pasteItem (:140)` (close first, post `.bufferIgnoreNextChange`) -> `PasteController.paste (:49)` (write pasteboard, `previousApp.activate`, +0.1s, CGEvent ⌘V). `previousApp` captured in `showWindow (:155)`.

Notifications (declared `HistoryWindow.swift:167-173`): `.bufferIgnoreNextChange`, `.bufferHotkeyChanged`, `.bufferWindowDidOpen`, `.bufferHistoryLimitChanged`, `.bufferStatusBarVisibilityChanged`.

## 2. DATA MODEL
`ClipboardItem` (struct, Identifiable, Codable, Equatable): `id: UUID`, `type: ClipboardItemType`, `timestamp`, `sourceApp: String?` (localizedName, not bundle id), `textContent: String?` (inline or 500-char preview), `textFilename: String?` (`texts/<uuid>.txt`), `imageFilename: String?` (`images/<uuid>.png`), `isPinned` (float to top, protected), `isBookmarked` (= star/favorite, protected), `tags: [String]` (also protects from eviction), `ocrText: String?`, `isTruncated`/`originalSizeBytes` (dead). Custom `init(from:)` `:59-74` / `encode` `:76-91` use `decodeIfPresent ?? default` -> **adding optional fields is migration-free**. Computed: `isFileBacked`, `isEditable` (text, not file-backed, <= 5000 chars), `previewText` (200 chars), `contentHash` (unused). Factories `.text .image .largeText`.

### Persistence: plain JSON
- `~/Library/Application Support/Buffer/`: `history.json` (whole array rewritten on every mutation, non-atomic, `saveHistoryToDisk :392-399`), `images/<uuid>.png`, `texts/<uuid>.txt`.
- `loadHistory :376-390`: decode error silently **discards all history**. No schema version field.
- Writes on `saveQueue` (utility); mutations on main via `runOnMain`; `add` uses `DispatchQueue.main.sync :72` (deadlock hazard).
- Thresholds (`ClipboardWatcher:19-20`): inline text <= 50,000 bytes; larger -> file + 500-char preview; large text hash uses first 10,000 chars. Detail pane chunks 2,000 chars.
- No image cache; thumbnails drawn off-main via lockFocus (`ClipboardItemRow:147-170`, fragile).

### History limit
`HistoryLimit` enum (`SettingsManager:6-26`): essential 100, deep 500, **"unlimited" = 1000 hard cap**. `ClipboardStore.maxItems :17`. Enforced in `performAdd :85-94` (evicts last unprotected; if all protected, evicts last anyway) and `handleLimitChanged :50-63`. Protection predicate `!isPinned && !isBookmarked && tags.isEmpty` duplicated at `:54, :86, :232, :236`. No scheduled cleanup, no orphan sweep.

## 3. FEATURE INVENTORY (must all survive)
- **Pin** `togglePin :136`, button `HistoryWindow:1048`, ⌘P; sorted to top (`:239`, invalid sort predicate); "Pinned" header `ClipboardListView:36-56`; row dot RGB(112,104,196).
- **Bookmark (= favorite/star)** `toggleBookmark :147`, button `:1055` (yellow bookmark.fill), ⌘B; labelled "save" in action bar `:1532`.
- **Tags** `allTags/addTag/removeTag :168-191`; `TagChip` 6-color palette hashed by unstable `hashValue`; inline add `:1609-1681`, ⌘T; Tab completion; filter by chip tap / `#query` / autocomplete bar `:1582-1606`; ⌫ clears filter.
- **Edit** (text <= 5000, not file-backed) `enterEditMode :1381`, `exitEditMode :1393` (auto-save AND overwrites system pasteboard), ⌘E; `updateText :158`.
- **Multi-select** `selectedIDs: Set<UUID>`, ⌘-click toggle, ⇧-click/⇧↑↓ extend (`ClipboardListView:67-83`, `GlobalKeyMonitor:1718-1733`); multi-selection summary pane `:1117-1273` with Download All + inline delete confirm; `delete([ClipboardItem]) :119`.
- **Multi-paste** Enter with selection -> `PasteController.pasteMultiple :83-156` (texts joined by "\n", images as temp file URLs, hardcoded delays). **Multi-copy does not exist** (⌘C copies first selected only).
- **Click behavior**: single click = select only (`ClickModifierDetector` overlay, `ClipboardListView:67-89`); double-click = `onSelect` -> copy to clipboard + close (`HistoryWindow:920`); paste only via Enter or PasteButton. MUST KEEP.
- **Save image to disk** `saveImageToDisk :194-221` (NSSavePanel PNG), ⌘S; batch `downloadAllImages :380-417`.
- **OCR** one-shot button `:1030-1046`, `setOCRText :194`; OCR text not searchable.
- **Search** inline `searchBar :844-903`, 200ms debounce; `computeFilteredItems :227-240` matches `textContent` only, **images excluded from any query**; `#` prefix = tag mode; state persists 90s after close.
- **Global hotkey** default ⇧⌘V, user-configurable (`HotkeyManager`, `SettingsView:32-79`).
- **In-window keys** hardcoded keycodes in `GlobalKeyMonitor :1715-1806`: ↑↓ (⇧ extend), Return (36), Esc (53), ⌘⌫ delete, ⌫ clear tag filter, ⌘C, ⌘P, ⌘B, ⌘S, ⌘T, ⌘E, Tab. Local NSEvent monitor.
- **Context menu**: only on the status bar item (`StatusBarController:68-114`): Shortcut label, Settings, Check for Updates, Pause/Resume Capture, Clear History, Quit. **No row context menu exists.**
- **Settings keys**: `hotkeyModifiers [String]`, `hotkeyKeyCode Int`, `historyLimit Int`, `includePrereleases`, `hideStatusBar`, `hasLaunchedBefore`, `lastUpdateCheckDate`, `bufferJustUpdated`, `bufferUpdateTag`; launch at login via `SMAppService`. Duplicate layer `SettingsViewModel` re-reads/writes same keys.
- **Hide menu bar icon**, **UpdateService** (self-replace from upstream GitHub releases), **Pause capture**.
- **Window**: `HistoryPanel: NSPanel` 700x480, floating, nonactivating, titled w/ hidden title & traffic lights, 10pt radius, closes on resignKey; recentred every show (size/position not persisted). Settings in separate NSWindow (`StatusBarController:120-135`).
- **Permissions**: only Accessibility, prompted unconditionally at every launch, result ignored, no guidance.

## 4. UI
Layout (`HistoryContentView :419-447`): VStack = searchBar / tagAutocompleteBar / Divider / HSplitView(listPane 280-350 | detailPane min 300) / Divider / actionBar (nav buttons + static shortcut legend + PasteButton). min 600x400. **No sidebar, no chip row.**
Colors: system NSColors + hardcoded (purple multi-select, pin RGB, yellow bookmark, orange Large badge, tag palette). No theme file. Fonts: ~60 hardcoded `.font(.system(size:))` literals (HistoryWindow ~45, ClipboardItemRow 5, TagChip 2, PasteButton 3, SettingsView).
Row: icon 20x20 (CSS color swatch / doc.text / image thumb) + 50-char single-line preview + first tag + `+N` + sourceApp + pin dot + bookmark badge.
**Non-image files unsupported**: only a single image file from Finder is converted to an image item (`ClipboardWatcher:88-98, 165-209`); other files become plain-text paths.

## 5. TESTS
`BufferTests/ClipboardItemTests.swift`: one Equatable test. Needs Xcode (`xcodebuild test`), no scheme checked in. Build script runs no tests.

## 6. RISKS / CHANGE MAPS
Structural: (1) HistoryWindow monolith - split first; (2) "recompute filtered + reset selection" duplicated 5x (`:468, :491, :544, :596`, `selectSingle`); (3) invalid sort predicate `:239`; (4) two settings sources of truth; (5) pbxproj drift; (6) dead code: `SearchField.swift`, `moveToTop :208-226`, `truncatedText`, `simulatePasteWithDelay :176-182`, `ClipboardListView.onPaste/onDelete`; (7) timing-based paste delays; (8) 1Hz timer per visible row; (9) off-main lockFocus; (10) `main.sync` in add; (11) whole-file non-atomic JSON rewrite, silent decode failure.

- **A. Folders**: `ClipboardItem.folderID: UUID?` (+Codable); new `Folder` model + `folders.json` in store; CRUD like tags; eviction predicates `:54, :86, :232, :236`; `computeFilteredItems`; all 5 selection-reset blocks; sidebar in `body :419-447`; `GlobalKeyMonitor`.
- **B. Lock**: `isLocked` + Codable; `toggleLock`; guards in `delete(_:) :105`, `delete([_]) :119`, `clear :228`, eviction predicates (extract `isProtected` first); UI button near `:1055`, shortcut, guard `onDelete :720` and multi-delete `:1233`; `StatusBarController.clearHistory :156-178` copy.
- **C. History limit**: `HistoryLimit :6-26`, `maxItems :17`, `performAdd`, `handleLimitChanged`, `SettingsView:141-187` + alert `:220-230`, duplicate in `SettingsViewModel :350-351, 363`. Scale blockers: whole-array rewrite, full decode, linear filter, sort predicate, row timers.
- **D. Custom shortcuts**: `GlobalKeyMonitor :1717-1805` -> binding table; `SettingsManager` action->binding dict + `keyCodeNames :146-154` (incomplete); `KeyRecorder :255-319`; legend `:1482-1560`, `.help()` strings, `StatusBarController:73`.
- **E. File items**: `case file` breaks exhaustive switches at `previewText :144`, `contentHash :158`, `itemSize :349`, `PasteController :34-45, :53-70`, `HistoryWindow.itemContent :1277`, `ClipboardItemRow.icon :122`; watcher `:88-98`; store copy-vs-reference, `deleteAssociatedFiles :414`; `PasteController` write NSURL/file promises; `:967, :1145, :1171, :1551, :234-237`, row `:101-104`.
- **F. Font size**: new setting in both settings layers; replace ~60 literals via a scale; row height/padding/truncation/icon frame are size-coupled.
- **G. Filter chips**: state near `:209`, chips row between `:422-429`, predicates in `computeFilteredItems`, all 5 reset blocks, backspace logic `:780, :1741`.
- **H. Plain-text paste**: capture is plain-only today (`ClipboardWatcher:101`); add `plainText` param to `paste :49`, `pasteMultiple :83`, `copyToClipboard :30`; controller signatures `:140-152`; Return handler must read modifiers `:686-707, :1734`; PasteButton variant; legend. Rich capture would add `rtfFilename`/flavors.
- **I. iCloud**: nothing exists; entitlements/pbxproj/build script for CloudKit; store functions `:21-36, 376-399, 251-298, 414` assume local single writer; whole-file JSON unmergeable without per-item merge; no tombstones; eviction is per-device; README/SECURITY claim local-only.

Suggested split: Agent 1 model/persistence (Models, ClipboardStore, ClipboardWatcher) first; Agent 2 HistoryWindow decomposition (blocking); Agent 3 filters/chips/folders UI; Agent 4 input/shortcuts/paste; Agent 5 theming/fonts; trailing chore: pbxproj sync + delete dead code.
