# Task 1A - Split `Views/HistoryWindow.swift` (Opus 5)

WORKTREE: (set at launch). Use absolute paths under it. Do NOT commit. Do NOT touch the main checkout at /Users/sam/Claude/Code/clipboard-manager.

Read first: `docs/analysis/buffer.md` (all), then `Views/HistoryWindow.swift` fully (1,914 lines), `Views/ClipboardListView.swift`, `Views/ClipboardItemRow.swift`, `Views/ClickDetector.swift`, `Views/PasteButton.swift`, `AppDelegate.swift`, `Views/StatusBarController.swift` (callers of the window controller).

## Goal
Decompose the monolith into small files with **zero behavior change**, so that Phase 2 (Clipfield-style UI) and Phase 3 (7 parallel feature agents) can work on separate files.

## Required outcome
Create `Views/History/` and move code there; delete `Views/HistoryWindow.swift`.

| New file | Contents |
|---|---|
| `Views/History/Notifications.swift` | the `Notification.Name` extension (`.bufferIgnoreNextChange` etc. - names unchanged) |
| `Views/History/HistoryPanel.swift` | `HistoryPanel: NSPanel` |
| `Views/History/HistoryWindowController.swift` | `HistoryWindowController` - public API used by `AppDelegate`, `StatusBarController` and the debug hooks (`showWindow`, `close`, `toggle`, `pasteItem`, `pasteMultiple`, `previousApp`) must keep the same names/signatures |
| `Views/History/HistoryViewModel.swift` | NEW `@MainActor final class HistoryViewModel: ObservableObject` holding the state that today lives as ~35 `@State` in `HistoryContentView` (search text + debounce, `activeTagFilter`, `filteredItems`, `selectedIDs`, `selectionAnchor`, `selectedItem`, edit mode + draft, tag input state, `savedSelectedID`, `shouldResetSearch`, preview image / chunked text state) and ALL the logic that mutates it: **one** `applyFilters(resetSelection:)` replacing the five duplicated recompute/selection-reset blocks (`:468-490, :491-510, :544-572, :596-628` and the partial in `selectSingle`), `selectSingle/toggleSelection/extendSelectionTo/extendSelectionUp/Down/clearSelection`, `enterEditMode/exitEditMode`, tag add/remove/complete, copy/paste/delete/pin/bookmark/save/OCR actions (they call the store / controller callbacks exactly as before) |
| `Views/History/FilterState.swift` | `struct FilterState { var query: String; var tag: String? }` + a pure `static func apply(_ items: [ClipboardItem], _ f: FilterState) -> [ClipboardItem]` (the current predicate: non-empty query matches `.text` items' `textContent` case-insensitively; `#` queries are tag mode; tag filter; pinned first). Pure function = unit-testable. Fix the invalid sort: replace `sorted { $0.isPinned && !$1.isPinned }` with a **stable partition** (pinned in original order, then the rest in original order) |
| `Views/History/HistoryContentView.swift` | the thin root view: `VStack { SearchBar; TagAutocompleteBar; Divider; HSplitView { ClipboardListView; DetailPane }; Divider; ActionBar }` + `.onChange`/`.onReceive` wiring, `frame(minWidth: 600, minHeight: 400)` |
| `Views/History/SearchBar.swift` | `searchBar` (:844-903) |
| `Views/History/TagAutocompleteBar.swift` | `:1582-1606` |
| `Views/History/DetailPane.swift` | `detailPane` (:936-1114) incl. header, action icon cluster, `itemContent` (:1277-1351) |
| `Views/History/MultiSelectionSummary.swift` | `:1117-1273` incl. Download All + inline delete confirm |
| `Views/History/TagSection.swift` | `:1609-1681` |
| `Views/History/ActionBar.swift` | `:1435-1578` (nav buttons, legend, PasteButton) |
| `Views/History/GlobalKeyMonitor.swift` | `GlobalKeyMonitor` + `Coordinator` (:1691-1861) - keep the hardcoded keycode switch for now (Phase 3E makes it table-driven); it should call view-model methods instead of a dozen closures where that is a pure refactor |
| `Views/History/RelativeTimestampView.swift` | `:1863-1913` |
| `Views/History/ChunkedTextState.swift` | `ChunkedTextState` (:22-23 region) |
| `Views/History/ArraySafe.swift` | `Array[safe:]` |

Also: remove the unused `onPaste`/`onDelete` parameters from `ClipboardListView` (and their call sites) - they are dead.

## Rules
- Zero behavior change. Every item in `docs/plan/PLAN.md` section 7 must still hold. Single click selects only; double click copies + closes; Enter / Paste button pastes; ⌘-click/⇧-click/⇧↑↓ multi-select; ⌘P/⌘B/⌘E/⌘T/⌘S/⌘C/⌘⌫/Esc/Tab unchanged; search debounce 200 ms and 90 s persistence; edit mode auto-exit on focus loss; tag autocomplete.
- Do not rename notification names, `ClipboardStore` API, `PasteController` API, `HistoryWindowController` public API.
- Keep `HistoryContentView`'s initializer compatible with how `HistoryWindowController` builds it (you own both, so adjust together).
- No new features, no styling changes, no new settings.
- Delete `Views/HistoryWindow.swift` with `git rm` after moving everything.

## Verify
1. `scripts/build_local.sh` - zero errors; warning count not above baseline (`build/compile.log`).
2. `scripts/run_tests.sh` - passes. Add `Tests/FilterStateTests.swift` covering: empty query returns all with pinned first and stable order; query matches only text items; `#tag` mode; tag filter; mixed.
3. Run `scripts/run_app.sh`; `notifyutil -p com.fxreza.klip.debug.show`; `echo "split-test $(date)" | pbcopy`; `screencapture -x build/shot1.png`; Read the screenshot and confirm the window shows the new item, the search bar, the detail pane and action bar; `notifyutil -p com.fxreza.klip.debug.hide`; `scripts/run_app.sh --kill`.
4. Self-review: `git diff --stat` and a careful read of each new file against the original for dropped `onChange` handlers, lost `@State` initial values, or changed ordering in `applyFilters`. List anything you are unsure about in the report.

Owns: `Views/History/**`, `Views/HistoryWindow.swift` (deleted), `Views/ClipboardListView.swift` (dead params only), `Tests/FilterStateTests.swift`.
Return: summary of the file map, any behavior you believe might differ, verification evidence, `git status --short`.
