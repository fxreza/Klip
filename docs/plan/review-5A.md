# Task 5A — Adversarial review of `baseline-v2.5.0..HEAD` (v3.0.0-beta1)

Reviewer stance: every finding below is a concrete failure scenario (inputs/state → wrong outcome), not a
style opinion. Where a number is quoted it was measured by a harness in this session, not estimated.

Scope notes:
- `docs/plan/review-2B.md` already verified the §7 UI-preservation checklist; this pass does **not** repeat it
  and instead hunts crashes, data loss, lock bypasses, persistence faults, 10,000-item performance,
  concurrency under `-default-isolation MainActor`, and updater/script safety.
- Task 4B reviews iCloud sync in depth. Sync appears here only at the **integration** level: store hooks,
  eviction vs sync-ignore, `applyRemoteMerge` vs locks, and quit-time push.
- The Mac screen was locked for the whole session, so nothing was confirmed with a real mouse/keyboard.
  Findings that need a live session are marked and listed again at the end.

## Method / evidence base

| What | How |
|---|---|
| Code trace | Full read of `ClipboardStore`, `ClipboardWatcher`, `ClipboardItem`, `SyncMerge`, `PasteController`, `PasteboardFlavors`, `ContentDetector`, `UpdateService`, `ShortcutManager`, `KeyBinding`, `GlobalKeyMonitor`, `HistoryViewModel(+Lock)`, `HistoryWindowController`, `FilterState`, `ClipList`, `ClipRow`, `FilePreview`, `RowContextMenu`, `StatusBarController`, `AppDelegate`, `CloudDriveSync` (integration surfaces), `scripts/*.sh` |
| Perf harness | `scratchpad/harness-5A/PerfHarness.swift` — 10,000 mixed items (500 image, 500 file, 500 link, 500 email, 500 code, 500 color, rest prose), 200 tags, 30 folders |
| Eviction harness | `scratchpad/harness-5A/{EvictHarness,GrowthHarness}.swift` |
| Persistence harness | `scratchpad/harness-5A/PersistHarness.swift` — 12 scenarios, v1 migration / corruption / missing assets / non-ASCII names / 5 MB text |
| Lock + merge harness | `scratchpad/harness-5A/LockHarness.swift` — every local delete path plus 7 `SyncMerge` scenarios |
| kill -9 harness | `scratchpad/harness-5A/KillHarness.swift` — 5 + 3 trials, SIGKILL at random points in the save debounce |
| Capture harness | `scratchpad/harness-5A/CaptureHarness.swift` — `ContentDetector` on 2–15 MB clips |

All harnesses ran against `KLIP_DATA_DIR` temp dirs. The user's real `~/Library/Application Support/Buffer`
and iCloud Drive were never read or written (the v1-migration shape was reconstructed from
`git show baseline-v2.5.0:Models/ClipboardItem.swift`, and `review-2B.md` already covered the real file).

---

## Findings

| id | sev | file:line | scenario (input/state → outcome) | suggested fix | confidence |
|---|---|---|---|---|---|
| **5A-01** | **Critical** | `Views/History/GlobalKeyMonitor.swift:27-233`, `Views/History/HistoryWindowController.swift:56-75,120-141` | The history panel is built once at launch and only *ordered out* on close, so its `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` stays installed for the process lifetime. A local monitor is **app-wide**, not window-scoped, and the handler never checks that the panel is key. Repro: ⇧⌘V → Esc (panel hidden) → select a clip earlier → ⌘S → the `NSSavePanel` opens (in-process; the app is not sandboxed) → press **Return** to accept the filename. `ShortcutManager.action(for:)` resolves keyCode 36/no-modifiers to `.paste`, `isEditing`/`isPromptShowing` are false, so the monitor returns `nil` (swallowing the event so the panel never saves) **and** calls `viewModel.keyEnter()` → `onPaste` → `close()` + `PasteController.paste` → the clip is pasted into whatever app was frontmost. The same hijack applies to: Return/Esc in the "Clear Clipboard History?" alert (`StatusBarController.swift:164-186`), the "Klip x.y is available"/"You're up to date" alerts (`UpdateService.swift:128-151`), the `NSOpenPanel` in `PasteController.saveFileToDisk`, and ⌘C/⌘S/⌘N/⌘R/⌘M/⌘E/⌘L/⌘P/⌘B/⌘1-9/⌥⌘S/⌥⌘P anywhere in Settings, Permissions or Onboarding. The `.copy` case's `responder is NSTextView` escape hatch reads `view.window?.firstResponder` — the *history panel's* responder, not the key window's — so it never fires for other windows. Pre-existing in `baseline-v2.5.0:Views/HistoryWindow.swift:1715`, but 3E widened the intercepted set from 8 keycodes to 34 actions. | Gate the whole handler on `view.window?.isKeyWindow == true` (or install/remove the monitor in `showWindow`/`close`). | High for the code path; the exact AppKit dispatch order into modal panels needs a live keyboard test |
| **5A-02** | **Critical** | `Services/ClipboardStore.swift:194-203,1299-1316,1359-1374` | `performAdd` calls `noteEvicted([removed.id])` **inside** the eviction loop, and `recordEvictions` → `saveSyncIgnore()` does a `saveQueue.sync` + full JSON re-encode of the entire `syncIgnoredIDs` dictionary (sorted by `uuidString`, allocating a string per comparison) — once per evicted item, on the main thread. State: `history.json` holds 10,000 unprotected clips while the effective limit is 1,000 (init never trims to the limit — `loadHistory` has no cap check — so this survives a relaunch). The very next clipboard copy evicts 9,000 items in one loop. **Measured: 117,996 ms (118 s) of main-thread block on one `store.add()`.** Even the fully-batched Settings path (`handleLimitChanged`) blocks main for **724 ms** at 9,000 evictions. | Hoist `noteEvicted` out of the loop in `performAdd` (collect ids, one call after), make `saveSyncIgnore` async on `saveQueue`, and trim to the limit once at the end of `loadHistory`. | High (measured) |
| **5A-03** | **High** | `Services/ClipboardStore.swift:1299-1316,1342-1374` | Steady state, no over-cap store needed, **and no iCloud sync required** — `noteEvicted` is guarded only by `!isApplyingRemoteMerge`, never by "sync is enabled". Once the history sits at its cap, *every* clipboard copy evicts one clip → prunes and rewrites the whole `sync-ignore.json` synchronously on the main thread. Measured with sync never attached, growth from an empty ignore list: copy #1 = 0.44 ms, #500 = 1.84 ms, #1000 = 3.34 ms, #2000 = 6.55 ms, #3000 = 8.53 ms (204 KB file); with 9,030 entries already present, **24 ms per copy** and a 0.6 MB file rewritten each time. Entries live 30 days (`SyncMerge.ignoreLifetime`), so a user who copies ~1,000 things a day reaches ~30,000 entries → ≈85 ms of UI stall on every ⌘C, forever. | Skip the sync-ignore bookkeeping entirely when `CloudDriveSync` was never enabled; otherwise debounce the write and keep the list as an append-only log or a bounded ring. | High (measured) |
| **5A-04** | **Critical** | `Services/ClipboardWatcher.swift:157`, `Services/ContentDetector.swift:140-183` | `ClipboardWatcher.checkClipboard` runs on the **main** run loop (`RunLoop.main.add(timer!, forMode: .common)`) and calls `ContentDetector.detect(for:fullText: text)` with the *entire* captured string. `isCode` then runs `hasSQLSelectFrom`'s non-greedy `\bSELECT\b[\s\S]*?\bFROM\b` over the whole clip, plus up to 22 full-string `contains` scans and a `components(separatedBy:"\n")` that allocates every line. **Measured: copying 14.9 MB of plain log text = 5,000 ms of main-thread freeze**; 3.2 MB of prose = 386 ms; 2 MB of JSON = 13 ms. The freeze happens on every copy of a large text clip (a log tail, a CSV, a `git diff`) — the menu bar, the panel and the hotkey are all dead for those seconds. Same call path also does `store.saveText(text)`, `pasteboard.data(forType: .rtf)` and `PasteboardFlavors.capture` on main. | Move the whole capture body (detection, `saveText`, `saveRTF`, `saveFlavors`) to a background queue and hop back to main only for `store.add`; cap detection input (e.g. first 64 KB) and anchor/replace the SQL regex. | High (measured) |
| **5A-05** | **High** | `Services/ClipboardStore.swift:1073-1106` | `loadHistory` decodes `[ClipboardItem]` as one unit. A **single** undecodable record loses the whole file: harness scenario 5 fed a v2 file with 3 items where item 2 has `"id":"not-a-uuid"` → 0 items loaded and the file quarantined as `history.corrupt-<stamp>.json`. The user sees a completely empty Klip — including every locked clip, which the app otherwise promises can never be lost. Reachable from a partially-written remote snapshot, a disk bit-flip, or any future field that stops being optional. Note the quarantine itself works correctly (verified for malformed, truncated, wrong-shape and corrupt-`folders.json` inputs) — the problem is the all-or-nothing granularity. | Decode item-by-item (`[FailableItem]` / `nestedUnkeyedContainer` with per-element `try?`), keep the good records, and report how many were dropped. | High (measured) |
| **5A-06** | **High** | `Services/SyncMerge.swift:206-207`, `Services/ClipboardStore.swift:1382-1398` | **Lock bypass via sync.** `SyncMerge` never consults `isLocked`: rule 3 drops any record whose tombstone is newer than the surviving copy's `updatedAt`. Harness C1: local clip is locked, `updatedAt = T+10`; Mac B publishes a tombstone at `T+20` (it deleted the clip before it saw the lock, or its clock is ahead) → the merged result contains 0 items and 1 `removedItem`. `applyRemoteMerge` then applies the result verbatim (harness C7 — no lock re-check in the store either) and calls `deleteAssociatedFiles(for: removed)`, so the image/text/file bytes go too. This contradicts `ClipboardStore.clear`'s stated contract ("a lock is absolute and outranks an explicit clear"). Harness C2 additionally shows a newer remote copy with `isLocked = false` silently clearing a local lock (whole-record newest-wins). | Filter locked ids out of the tombstone application in `SyncMerge.merge` (or re-check in `applyRemoteMerge`) and surface a "N locked clips were deleted on another Mac — kept here" notice; treat `isLocked` as a sticky OR rather than a whole-record field. | High (measured) |
| **5A-07** | **High** | `Views/History/ClipRow.swift:238-262` | `loadThumbnail()` calls `thumb.lockFocus()` / `original.draw(...)` / `thumb.unlockFocus()` inside `DispatchQueue.global(qos:.userInitiated)`. `NSImage.lockFocus` pushes an `NSGraphicsContext` and is documented main-thread-only; doing it concurrently from several rows while the main thread is also drawing is the classic off-main-AppKit crash/corruption pattern. Trigger: scroll a history that contains many image clips — every row that scrolls into view spawns one of these (LazyVStack discards `@State`, so it re-runs each time). Carried over from upstream `ClipboardItemRow`, but the new 38×38 badge means more rows render at once. | Render into an `NSBitmapImageRep` + explicit `NSGraphicsContext`, or use `CGContext`/`CGImageSourceCreateThumbnailAtIndex` (thread-safe), or hop to main for the draw. | High (code-evident); a crash was not reproduced headlessly |
| **5A-08** | **High** | `Services/ClipboardWatcher.swift:264-272`, `Services/ClipboardStore.swift:853-942` | `processFileURLs` calls `store.makeFileItem(from:)` — which **copies every file into `files/<uuid>/` first** — and only afterwards checks `guard fingerprint != lastFileFingerprint`. A repeat ⌘C of the same files in Finder therefore writes a second full copy and then throws the item away, leaving `files/<uuid>/` orphaned. **Measured** (harness scenario 10): `files/` went from 1 to 2 directories after a duplicate capture that produced no new clip. Nothing ever collects these — there is no orphan sweep anywhere in the codebase (grep for `orphan|sweep|garbageCollect` finds only comments). Copy a 500 MB folder twice → 1 GB used, 500 MB unreachable. The same applies to `images/`, `texts/` and `flavors/` files written before a kill -9 lands in the 300 ms save debounce (5A-13). | Compute the fingerprint from the URL list *before* copying, and add a launch-time sweep that deletes `images|texts|files|flavors` entries no item references. | High (measured) |
| **5A-09** | **High** | `Services/ClipboardStore.swift:912-942` | Copying two files with the same basename in one Finder selection (`~/a/report.pdf` + `~/b/report.pdf`) makes the second `copyItem` throw `NSFileWriteFileExists`; `copyIntoStorage` then deletes the whole destination directory and returns `nil`, so the caller falls back to a **reference to only the first file**. **Measured** (harness scenario 11): `storedRelativePath == nil`, `isReference == true`. The row still reads "report.pdf +1" and `additionalNames` still lists the second file, but `fileURLs(for:)` can only ever return the first — the second file is silently unrecoverable from the clip, and if the user then moves/deletes the originals the clip is worthless. | De-duplicate names inside `copyIntoStorage` (`report 2.pdf`, mirroring `PasteController.uniqueURL`) instead of failing the whole copy; and store one reference *per* file rather than only the first. | High (measured) |
| **5A-10** | **High** | `Views/History/ClipRow.swift:28,63-71,238-262` vs `Views/History/FilePreview.swift:19-23` | `.file` thumbnails go through an `NSCache` (countLimit 500), but **image** thumbnails do not: `@State private var thumbnail` lives inside the row, and `LazyVStack` throws the row's state away when it scrolls out of view. Every scroll back re-reads the full-resolution PNG from disk (`NSImage(contentsOf:)`) and re-renders it. With a history full of screenshots this is continuous disk + CPU churn while scrolling and defeats the point of `.task(id:)`. Harness RSS stayed modest (30 → 70 MB for a 10,000-item text-heavy fixture, no leak observed) — the cost here is repeated I/O and decode, not retained memory. | Give image thumbnails the same `NSCache` treatment as `FilePreview.thumbnail`, keyed by item id + badge size. | High (code-evident) |
| **5A-11** | **High** | `Services/UpdateService.swift:338-357` | The generated install script does `rm -rf "/Applications/Klip.app"` and *then* `cp -R`. If the copy fails (disk full, the extracted bundle was moved, permissions), the user is left with **no** app at all — only an `osascript` alert saying to update manually. `rm -rf` also returns 0 when the path doesn't exist, so the `$?` check catches almost nothing. | Copy to `/Applications/Klip.app.new`, then `mv` the old one aside, `mv` the new one in, and only then delete the old — restoring the old bundle if any step fails. | High (code-evident) |
| **5A-12** | **High** | `Services/UpdateService.swift:324-335` | `codesign --verify --deep --strict <newApp>` only proves the signature is internally consistent; an **ad-hoc or any self-signed** bundle passes. There is no identity/anchor requirement, so the check cannot distinguish a genuine Klip build from any other signed app that ends up at that download URL (a compromised or mis-attached GitHub release asset). Also, the downloaded zip's size and content type are never validated, and `--deep` verification is deprecated by Apple. | Add `--requirement 'anchor apple generic and certificate leaf[subject.CN] = "…"'` (or pin the exact self-signed leaf's SHA-256), and refuse to install on mismatch. | High (code-evident) |
| **5A-13** | Medium | `Services/ClipboardStore.swift:989-1007` | The 300 ms save debounce is trailing-only with **no maximum delay**: every `scheduleSave()` cancels the pending work item and re-arms it. Harness: adding a clip every 10 ms for ~2.4 s produced 240 in-memory clips and **zero** on disk — `history.json` was still byte-identical to the seed when `kill -9` landed (5 trials). At the realistic 500 ms watcher cadence the debounce behaves correctly: 3 trials adding a clip every 600 ms and SIGKILLing at a random point lost **nothing** (6, 6 and 7 live clips in memory, all 6/6/7 on disk), and `.atomic` writes meant the file was never torn. So the normal path is safe, but any burst source faster than 300 ms (a rapid remote-merge loop, a scripted mutation) starves the write indefinitely. | Add a max-wait: if the first pending mutation is older than ~2 s, write regardless of new activity. | High (measured) |
| **5A-14** | Medium | `Views/History/ClipList.swift:32` | `ForEach(Array(items.enumerated()), id: \.element.id)` materialises a fresh 10,000-element array of `(Int, ClipboardItem)` tuples on **every** `ClipList` body evaluation, and `items.contains(where: { $0.isPinned })` (line 28) re-scans the list each time too. `hoveredID` is `@State` on `ClipList`, so simply moving the mouse across rows re-evaluates the body — 10,000 struct copies per hover transition, on the main thread. | Use `ForEach(items) { item in … }` and derive the index only where needed (the pinned-separator check can use the item's own `isPinned` plus a precomputed pinned count); hoist the hover state into the row. | High (code-evident) |
| **5A-15** | Medium | `Views/History/FilterState.swift:122-136,180-183` | `searchBlob(for:)` rebuilds and `.folding(...)`s a new String for **every** item on **every** keystroke; nothing is cached. Measured at 10,000 items: 1-char query 9.4 ms, 4-char 16.9 ms, two words 24.9 ms, no-match query **35.6 ms**, and 112 ms of total main-thread work to type "project" (7 keystrokes; the 200 ms debounce coalesces some of this in the real app but the worst-case single pass is still 35 ms). Scope/tag/chip-only filters are cheap (0.3–0.5 ms). Worst case scales with clip size: an inline clip can be up to 50 KB (`inlineTextLimit`). | Cache the folded blob per item id (invalidate on `updatedAt`), or fold the query once and use `range(of:options:.caseInsensitive)` instead of building folded copies. | High (measured) |
| **5A-16** | Medium | `AppDelegate.swift:117-130`, `Services/CloudDriveSync.swift:447-451,838-870` | `applicationWillTerminate` calls `CloudDriveSync.shared.pushSynchronously()` **on the main thread**. `performPush` → `pushAssets` → `copyWithTimeout`, which waits on a semaphore for up to `fileTimeout = 20 s` **per file**. A quit with several assets iCloud has not materialised blocks the main thread for `n × 20 s`; the app beachballs and can be SIGKILLed by the system before the push finishes. `stop()` (called one line earlier) cancels the debounces but does not wait for an in-flight `ioQueue` push/pull, so a second `performPush` can be running concurrently — both write the same `devices/<id>/history.json` and both mutate `knownCloudAssets`, which is documented as "`ioQueue` only" (`CloudDriveSync.swift:137`). | Bound the total quit-time push (single overall deadline, e.g. 2 s), and serialise `pushSynchronously` onto `ioQueue` with a bounded wait so it cannot race an in-flight cycle. | High (code-evident); integration-level only — 4B owns sync depth |
| **5A-17** | Medium | `Services/SyncMerge.swift:289-305`, `Models/ClipboardItem.swift:243-255` | Documented rule 5 ("content dedupe") **never fires for `.file` items**. `dedupeKey` builds `"file:\(item.contentHash):\(byteSize)"`, and `contentHash` for a file attachment hashes `storedRelativePath ?? referencePath ?? originalName` — `storedRelativePath` is `files/<item-uuid>`, unique by construction. Harness C4: the same file copied on two Macs stays two records forever. Every synced file therefore accumulates one copy per device, both on disk and in the list. (`contentHash` also uses `String.hashValue`, which is per-process seeded — fine inside one merge, as the comment says, but it means the key is not stable across runs.) | Key file dedupe on `(originalName, additionalNames, byteSize)` (what `sameContent` already compares), not on the storage path. | High (measured) |
| **5A-18** | Medium | `Services/SyncMerge.swift:289-321,372-385`, `Services/ClipboardStore.swift:1388-1390` | Image cross-device dedupe is destructive **by construction**. `dedupeKey` for `.image` is `"img:\(imageFilename)"` and `sameContent` also requires equal `imageFilename` — so the only images that ever fold are two ids pointing at the *same* `images/<name>.png`. `fold` keeps the older record; the newer one lands in `removedItems`; `applyRemoteMerge` then calls `deleteAssociatedFiles(for: removed)`, which deletes `images/<name>.png` — **the surviving item's own file**. Harness C5 confirms `removedItems[0].imageFilename == items[0].imageFilename`. Result: the survivor renders a grey placeholder and pastes nothing. The same shape applies to `.text` folds where the loser is the *local* record: its `texts/*.txt` is deleted while the survivor points at a remote file that must still be downloaded (harness C3). | Before deleting assets in `applyRemoteMerge`, subtract any filename/`storedRelativePath` still referenced by a surviving item. | High (measured); reachability of two ids sharing one `imageFilename` is low but the deletion is unconditional once it happens |
| **5A-19** | Medium | `Views/History/ClipList.swift:173-180` | `.contextMenu { let _ = viewModel.selectForContextMenu(item.id); RowContextMenu(...) }` mutates observable view-model state (selection) from inside a `ViewBuilder`. SwiftUI does not guarantee that context-menu content is only built on right-click; when it is evaluated during a normal body pass this is the "Modifying state during view update" pattern, which produces undefined selection behaviour and runtime warnings. | Move the selection into an `onTapGesture(.rightClick)`/`onHover`-style side effect, or wrap it in `DispatchQueue.main.async`. | Medium — needs a live session to confirm whether SwiftUI eagerly evaluates it here |
| **5A-20** | Medium | `Services/ClipboardWatcher.swift:136,163` | Still open from `review-2B.md`: `PasteboardFlavors.capture` enforces the 16 MB cap on the raw-flavors bundle, but the RTF captured alongside it (`pasteboard.data(forType: .rtf)` → `store.saveRTF`) has no cap of its own. A large RTF from an unusual source app is written to `texts/<uuid>.rtf` uncapped, and (with sync on) uploaded. | Apply the same `PasteboardFlavors.maxRawBytes` check to `rtfData` before `saveRTF`. | High (code-evident, re-confirmed at HEAD) |
| **5A-21** | Medium | `Services/PasteController.swift:163-181,200-209,238-244` | In the multi-item paste path, `writeURLBatchAndPaste` writes the pasteboard **first** and only then calls `simulatePasteWithCustomDelay(0.05)`, which posts `.bufferIgnoreNextChange` 50 ms later. The watcher polls every 500 ms, so roughly 10 % of multi-pastes containing images/files leave a window where the poll sees the new `changeCount` with `ignoreNextChange` still false and captures the app's own paste as a new clip (a text clip containing file paths, since `writeFileURLs` sets `.fileURL` + `.string`, not `NSFilenamesPboardType`). Single-item paste is safe — `HistoryWindowController.pasteItem` posts the flag before the write. | Post `.bufferIgnoreNextChange` immediately before `pasteboard.clearContents()` in `writeURLBatchAndPaste`, as the single-item path does. | High (code-evident) |
| **5A-22** | Medium | `Views/History/HistoryViewModel.swift:362-368,382-388` | `extendSelectionUp` / `extendSelectionDown` index `filteredItems[selectedIndex]` directly, while their siblings `navigateUp`/`navigateDown` (lines 409-427) use `[safe:]`. `applyFilters(.preserve)` returns early via `guard let id = selectedID else { return }` **without** re-clamping `selectedIndex`, so any future path that leaves `selectedID == nil` with a stale non-zero index turns ⇧↑ into an out-of-range crash. No repro exists today (`clearSelection()` is dead code and every other reset path sets index and id together), so this is a latent crash, not a live one. | Use `[safe:]` in both, and clamp `selectedIndex` at the top of `applyFilters` right after `filteredItems` is assigned. | High (code-evident); not currently reachable |
| **5A-23** | Medium | `Services/PasteController.swift:326-331` | Single-file "Save to Disk": after the user confirms the `NSSavePanel`, the code does `removeItem(at: destination)` **before** `copyItem`. If the copy then fails (source vanished, permissions, disk full) the user's pre-existing file at that path is already gone and nothing is written in its place. | Copy to a sibling temp name and `replaceItemAt` (or only remove after a successful copy). | High (code-evident) |
| **5A-24** | Medium | `Services/ClipboardStore.swift:1154-1166,1359-1374` | `saveFolders()` and `saveSyncIgnore()` both use `saveQueue.sync` from the main thread, and `saveQueue` is the same serial queue the debounced 10,000-item history write runs on. Creating/renaming/reordering a folder therefore blocks the UI until any in-flight history encode finishes. Measured `createFolder` at 10,000 items = 0.3 ms in the harness (the debounced write had already drained), so this is a latency spike rather than a steady cost — but it is unbounded by construction and is the same queue 5A-03 hammers. | Make both writes `saveQueue.async` (they are already snapshot-based, so nothing needs the result). | Medium |
| **5A-25** | Low | `Services/UpdateService.swift:338-357,376-379` | The install script interpolates `newAppURL.path` inside `"…"` and the launcher interpolates `scriptURL.path` inside `'…'` with no escaping. Both paths are `NSTemporaryDirectory()/KlipUpdate_<UUID>/…`, which in practice contains no spaces, quotes, `$` or backticks, so this is not exploitable today — but it breaks (or injects) if `TMPDIR` ever contains one. `$(id -u)` is correctly outside quotes. | Pass the paths as `"$1"`/`"$2"` positional arguments to the script instead of interpolating them into its text. | High (code-evident); not currently exploitable |
| **5A-26** | Low | `scripts/build_local.sh:110` | `*.swift $(find Models Services Views -name "*.swift" \| sort)` is unquoted word-splitting; any source file with a space in its name would silently break the build (or compile the wrong set). `scripts/run_tests.sh` does this correctly with `-print0`/`read -d ''`. | Mirror `run_tests.sh`'s null-delimited array. | High |
| **5A-27** | Low | `Views/History/GlobalKeyMonitor.swift:23-25` | The monitor is installed inside `DispatchQueue.main.async { guard view.window != nil else { return } … }` with no retry. If the hosting view is not yet in a window when that block runs, **every** in-window shortcut is dead for the rest of the session and nothing reports it. Works today because `HistoryWindowController.setupContent` attaches the hosting view before first display. | Install the monitor from `HistoryWindowController.showWindow`/`close` instead (which also fixes 5A-01). | High |
| **5A-28** | Low | `Services/ClipboardStore.swift:708-751` | When a large-text clip's backing `texts/<uuid>.txt` is missing, `fullText` falls back to the inline preview (good) but `textChunk` returns `nil` — the preview pane renders **empty** with no error, while paste still works from the preview. Measured in harness scenario 8. | Fall back to `item.textContent` in `textChunk` too and badge the pane "backing file missing". | High (measured) |
| **5A-29** | Low | `Services/ClipboardWatcher.swift:12-20,238-271` | `lastContentHash` and `lastFileFingerprint` are written on the main thread but **read** from `DispatchQueue.global` inside `processImageFile` (line 240) and `processFileURLs` (line 266). Under `-default-isolation MainActor` these are unsynchronised cross-actor reads of a non-Sendable class's state; the practical effect is a missed or spurious duplicate suppression, not corruption. | Capture the value on main and pass it into the background closure, or do the comparison on main. | High (code-evident) |
| **5A-30** | Low | `Views/History/RowContextMenu.swift:49-59,106-113` | Pin and Star act on the right-clicked `item`, while Lock, Move to Folder, Delete and Save to Disk act on the whole **selection**. Right-click inside a 10-item multi-selection → "Pin to Top" pins one row, "Lock" locks all ten. The label ("Lock"/"Unlock") is also derived from `item.isLocked` while the action is a selection-wide toggle. | Make Pin/Star selection-aware too, or label the selection-wide entries "Lock 10 Clips". | High |
| **5A-31** | Low | `Services/PasteboardFlavors.swift:39-59` | `capture` accumulates every flavor of every pasteboard item into a dictionary and only then checks `total <= maxRawBytes`, so a pasteboard far larger than the 16 MB cap is fully materialised in memory before being discarded — on the main thread. I could not demonstrate a spike headlessly (a synthetic 120 MB local pasteboard returned `nil` in 1 ms with no RSS growth, because the synthetic items produced no data), so this is code-evident only. | Track the running total and bail out as soon as it exceeds the cap. | Low — not reproduced |
| **5A-32** | Low | `Views/History/FilePreview.swift:72` | `QLPreviewView(frame: .zero, style: .normal)!` force-unwraps a failable initialiser. Documented as "doesn't fail in practice", and it is only reached when a `.file` item is previewed, but it is an unrecoverable crash if it ever does. | Return an empty `NSView` placeholder on `nil`. | High |

---

## PLAN.md §7 preservation checklist

`review-2B.md` verified all 12 against the code as merged through 3D/3E/3F/3G/3H. This pass re-checks them
against **HEAD** (which adds 4A sync) and against the findings above. Verdicts here are additive to 2B's.

| # | Item | Verdict | Evidence |
|---|---|---|---|
| 1 | ⇧⌘V toggles the panel; hotkey change takes effect immediately | VERIFIED | `HotkeyManager` untouched by every phase; `AppDelegate.swift:101-103` re-registers on `.bufferHotkeyChanged`. `ShortcutManager` deliberately does not own the global hotkey (`ShortcutManager.swift:146-148`). |
| 2 | Copy appears at the top within 0.5 s; duplicates dedupe | **AT RISK** | Dedupe verified (`ClipboardWatcher.swift:128,180,266`). The 0.5 s promise breaks under **5A-04** (a 15 MB text clip freezes the capture thread for 5 s) and under **5A-02/5A-03** (24 ms–118 s of eviction bookkeeping per add once at cap). |
| 3 | Single click selects only; double-click copies + closes; Enter pastes; Paste button pastes | VERIFIED | `ClipList.swift:110-165` — `ClickModifierDetector` overlay selects, `TapGesture(count:2)` copies + dismisses, nothing in the list pastes. Unchanged by 3B/3D/3E. |
| 4 | ⌘-click / ⇧-click / ⇧↑↓ multi-select; summary counts; Enter pastes all; Download All | VERIFIED with a latent crash | `HistoryViewModel.swift:322-398`, `MultiSelectionSummary.swift`. See **5A-22** for the unguarded `filteredItems[selectedIndex]` in ⇧↑/⇧↓. |
| 5 | ⌘P pin, ⌘B star, ⌘E edit, ⌘T tag + Tab + `#tag` + ⌫, ⌘S save image, OCR | **REGRESSED (5A-01)** | Every binding dispatches correctly inside the panel (`GlobalKeyMonitor.swift:104-167`, `ShortcutTests`/`KeyMonitorTests`), but ⌘S's `NSSavePanel` cannot be confirmed with Return, and the swallowed Return pastes the clip into the previous app instead. ⌘E/⌘L/⌘P/⌘B also fire while other windows are focused. |
| 6 | Search debounced, persists 90 s after close, selection restored | VERIFIED | `HistoryViewModel.swift:43-70`, `HistoryWindowController.swift:38-41,162-191`. Cost of each debounced pass measured at 9–36 ms/10k items (**5A-15**). |
| 7 | Large text (> 50 KB) stored as file, chunked preview, pastes in full | VERIFIED | Harness scenario 9: a 5 MB clip saved in 1 ms, `textChunk` returned exactly 2,000 chars, `fullText` round-tripped all 5,280,000 chars. Missing-backing-file case is **5A-28**. |
| 8 | Settings: hotkey, history limit + downgrade warning, prereleases, hide icon, launch at login | VERIFIED with a cost | All round-trip (`SettingsView.swift`, `SettingsManagerTests`). The downgrade itself blocks main for 724 ms at 9,000 evictions (**5A-02**). |
| 9 | Status bar: left-click toggles; right-click menu (Settings, Check for Updates, Pause/Resume, Clear History, Quit) | VERIFIED, keyboard AT RISK | `StatusBarController.swift` has all entries plus 3G's "Permissions…". The Clear History and update `NSAlert`s are subject to **5A-01** (Return/Esc hijacked). |
| 10 | Existing `history.json` from v2.5.0 loads without loss | VERIFIED | Harness scenario 1 against the exact baseline field set (`isTruncated`, `originalSizeBytes` present, no `updatedAt`): all 3 items loaded, unicode/pin/star/tags/ocrText preserved, `updatedAt` seeded from `timestamp`, re-saved as `{"version":2,…}`. `review-2B.md` separately verified this against the user's real 32-item file. Caveat: **5A-05** (one bad record loses everything). |
| 11 | Esc closes (after exiting edit / tag input); clicking outside closes | VERIFIED | `HistoryViewModel.keyEscape` unwinds edit → tag input → prompt → dismiss; `HistoryPanel.resignKey` → `onClickOutside` with the 0.4 s suppression window. Confirmed by 2B's behaviour harness. |
| 12 | Update check does not point at upstream | **VERIFIED** (2B left this open) | `UpdateService.swift:8,10` — `https://api.github.com/repos/fxreza/Klip/releases` and `https://github.com/fxreza/Klip`. `stripTagPrefix` handles `klip-v`, `buffer-v` and bare `v`. Grep finds no `samirpatil` in any runtime path. Separate concerns: **5A-11**, **5A-12**. |

### Lock-bypass sweep (every path that removes an item or its files)

Enumerated and exercised in `LockHarness.swift`. **Every local path is correct**:

| Path | Result |
|---|---|
| `delete(_ item:)` | returns `false`, item survives |
| `delete(_ items:)` batch | `deleted: 0, skippedLocked: 1`, item survives |
| `clear(keepProtected: true)` | survives |
| `clear(keepProtected: false)` | survives (lock outranks an explicit clear) |
| cap eviction (`performAdd`, 1,500 adds over a 1,000 cap) | survives |
| `handleLimitChanged` / `trimToLimitAfterMerge` | both key off `isProtected`, which includes `isLocked` |
| `deleteFolder(.deleteItems(includeLocked: false))` | clip **and** folder both survive, `skippedLocked: 1` |
| `deleteFolder(.deleteItems(includeLocked: true))` | deletes — correct, this is the second-confirm branch |
| `deleteFolder(.moveItemsOut)` | clears `folderID`, keeps the lock |
| `clearRichFlavors` (edit-mode save) | drops only `rtfFilename`/`flavorsFilename`, item survives |
| `updateText` on a locked item | allowed by design (a lock blocks deletion, not editing) |
| migration / corrupt-file handling | no deletion path; the bad file is quarantined, not removed |
| UI surfaces (⌘⌫, row menu, preview trash, multi-select confirm, Clear History) | all funnel through `performDelete(ids:)` → `store.delete` |

**Holes are all on the sync side**: **5A-06** (a remote tombstone deletes a locked clip and its bytes;
`applyRemoteMerge` re-checks nothing), and **5A-18** (fold deletes a surviving item's asset).

---

## Performance numbers (10,000 items, `-O`, Apple silicon, `KLIP_DATA_DIR` temp dir)

Fixture: 10,000 items — 500 image, 500 file, 500 link, 500 email, 500 code, 500 color, 7,000 prose
(8–68 words each); 200 tags spread over ~1,350 items; 30 folders with ~325 locked/foldered items;
200 pinned, 589 starred. `history.json` = **4.3 MB**.

| Operation | Result |
|---|---|
| Encode + atomic write, 10,000 items | 35.9 ms |
| `ClipboardStore()` launch load (read + decode + folders + sync-ignore) | **38.4 ms** |
| RSS after load | 63.1 MB (30.1 MB before) |
| `applyFilters` — no query, scope All | 1.0 ms |
| `applyFilters` — 1-char query | 9.4 ms |
| `applyFilters` — 4-char query | 16.9 ms |
| `applyFilters` — 2-word query | 24.9 ms |
| `applyFilters` — query matching nothing (worst case, scans every blob) | **35.6 ms** |
| `applyFilters` — chip only / tag only / folder scope | 0.4 / 0.3 / 0.5 ms |
| Typing "project" (7 keystrokes, uncoalesced) | 112 ms total |
| `store.add` + `flushPendingSave` (steady state, under cap) | 21 ms + 11 ms |
| `createFolder` at 10,000 items (`saveQueue.sync`) | 0.3 ms |
| Limit 10,000 → 1,000 via Settings (batched `handleLimitChanged`, 9,000 evictions) | **724 ms** main-thread block |
| `store.add` at cap, sync-ignore holding 9,030 entries | **24 ms** per clip, main thread |
| `store.add` at cap, sync-ignore growth from empty | 0.44 ms (#1) → 3.34 ms (#1000) → 8.53 ms (#3000) |
| First `store.add` with the store 9,000 items over cap | **117,996 ms (118 s)** main-thread block |
| RSS after 10,000-item load + full filter sweep + 3,000 adds | 69.6–90.2 MB (no growth trend) |
| `ContentDetector.detect` on 14.9 MB of log text (main thread, at capture) | **5,001 ms** |
| `ContentDetector.detect` on 3.2 MB of prose | 386 ms |
| `ContentDetector.detect` on 2.0 MB of JSON / 1.9 MB of source | 13 ms / 30 ms |
| `saveText` of a 5 MB clip | 1 ms |
| kill -9 during the save debounce, 600 ms cadence (3 trials) | **no loss** — 6/6, 6/6, 7/7 clips on disk, file never torn |
| kill -9 during the save debounce, 10 ms cadence (5 trials) | **total loss** — 189–259 clips in memory, 0 on disk (debounce starvation, 5A-13) |

Memory verdict: no leak or unbounded growth was observed at 10,000 items; the memory concern is **5A-10**
(image thumbnails re-decoded from disk on every scroll rather than cached) and **5A-08/5A-31**
(unbounded *disk* growth from orphaned assets, and a transient spike in flavor capture).

---

## Persistence / corruption results (`PersistHarness.swift`, 12 scenarios, all behaved as reported)

| Scenario | Outcome |
|---|---|
| v1 bare array with the exact baseline field set | 3/3 items, unicode + flags + tags + `ocrText` intact, `updatedAt` seeded from `timestamp`, re-saved as v2 |
| Malformed JSON | empty store, quarantined as `history.corrupt-<stamp>.json`, store usable afterwards |
| Truncated JSON (torn write) | same — nothing silently overwritten |
| Valid JSON, wrong shape (`["a","b"]`) | same |
| **One bad record among three good ones** | **all 3 lost** — see 5A-05 |
| Corrupt `folders.json` | no folders, quarantined as `folders.corrupt-<stamp>.json`, history unaffected |
| Item pointing at a deleted folder | item survives, stays `isProtected`, `folderCounts()` reports a phantom folder; recoverable via the row menu's "Remove from Folder" (`RowContextMenu.swift:67-72`), so not a trap |
| Missing image / text file / file payload | `image(for:)` nil, `fullText` falls back to the preview, `fileIsMissing` true — no crash. `textChunk` returns nil (5A-28) |
| 5 MB text clip | saved in 1 ms, chunked read exact, full text round-trips |
| Non-ASCII names (`Ünïcode Ärchïv.txt`, `日本語のファイル.txt`, `spaces and 'quotes".txt`, `emoji 🚀 file.txt`) | all 4 copied and resolved; **repeat capture leaked an orphan directory** (5A-08) |
| Two files with the same basename in one copy | silently degraded to a reference to the first (5A-09) |
| `KLIP_DATA_DIR` | tilde expanded via `expandingTildeInPath`; a relative value produces a relative `URL(fileURLWithPath:)` resolved against the process cwd — acceptable for a test-only override, worth documenting |

---

## Not verifiable without a live session (screen was locked)

1. **5A-01's exact AppKit dispatch order** — that a local key monitor really does intercept Return inside an
   in-process `NSSavePanel`/`NSAlert` modal session. The code path is unambiguous; the interception order is not.
   *This is the single most important thing to confirm before release.*
2. **5A-07** — whether off-main `NSImage.lockFocus` actually crashes on this macOS version under scroll load,
   or only produces occasional blank/garbled badges.
3. **5A-19** — whether SwiftUI eagerly evaluates the `.contextMenu` builder (and therefore
   `selectForContextMenu`) during a normal body pass on macOS 13/14.
4. Drag-and-drop end to end (`ClickModifierDetector` → `NSDraggingSession` → sidebar drop) — code-traced by 2B,
   still never exercised with a real mouse.
5. Rich paste fidelity into Pages/Mail/Word, and whether the synthesized ⌘V in `PasteController.simulatePaste`
   is misread as ⌥⌘V when the user triggered it with ⌥↩ while still holding ⌥ (flags are set explicitly on both
   events, so this is probably fine, but only a live test proves it).
6. Real two-Mac sync convergence, and the quit-time push stall in **5A-16** against a real iCloud container.
7. `QLThumbnailGenerator` behaviour and the 500-entry thumbnail cache under real scrolling.
8. Accessibility-denied paste flow and the toast rate limiting.

---

## Suggested fix order for 5C

1. **5A-01** (key monitor scope) — breaks Save/Clear/Update dialogs and pastes into the wrong app.
2. **5A-02 + 5A-03** (eviction bookkeeping on the main thread) — one change fixes both: batch `noteEvicted`,
   make `saveSyncIgnore` async, and skip it entirely when sync was never enabled.
3. **5A-04** (capture off the main thread) — 5 s freezes on ordinary large clips.
4. **5A-05** (per-item decode) — protects against total history loss.
5. **5A-06** (locks vs tombstones) — the only remaining lock bypass; coordinate with 4B.
6. **5A-11 / 5A-12** (updater safety) — before any release is published.
7. **5A-07 / 5A-08 / 5A-09 / 5A-10** — off-main drawing, disk leaks, silent file loss, thumbnail cache.
8. The Mediums, then the Lows.
