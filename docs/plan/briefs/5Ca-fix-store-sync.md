# Task 5Ca - Fix pass A: store, persistence, capture performance, sync (Opus 5)

WORKTREE: (set at launch). Do NOT commit. Do NOT touch the main checkout. Never write to the user's real `~/Library/Application Support/Buffer` or iCloud Drive (`KLIP_DATA_DIR`/`KLIP_CLOUD_ROOT` temp dirs only).

Read first: `docs/plan/review-5A.md` (all findings), `docs/plan/review-4B.md`, `docs/plan/briefs/5C-fix-pass.md` (items 1, 2, 5 are yours). A sibling agent (5Cb) concurrently owns `Views/**`, `Services/UpdateService.swift`, `Views/History/GlobalKeyMonitor.swift` and the *text* capture path's threading in `Services/ClipboardWatcher.swift` (5A-04). You own everything else.

## Your findings (fix all; add a regression test for each testable one)
- **5A-02** (Critical) `performAdd` eviction loop: `noteEvicted` per item does a sync save - batch the ids, write `sync-ignore.json` once, asynchronously on `saveQueue`; trim to the cap once in `loadHistory` so a store that is over the cap at launch never evicts thousands inside one `add()`. Target: adding one clip to a 10,000-item store over cap must take < 20 ms on main (measure and report).
- **5A-03** (High) sync-ignore bookkeeping must be a no-op when sync has never been enabled (`SettingsManager.syncEnabled == false` and no device dir ever created); when enabled, debounce the write.
- **5A-05** (High) per-item failable decode in `loadHistory` (and `folders.json`): a malformed record is skipped and logged (quarantine a copy of the raw file once), the rest load. Test: 3 items + 1 bad -> 3 loaded.
- **5A-06 / 4B #3** (High) sync lock bypass: in `SyncMerge` a tombstone never removes a record whose surviving state is `isLocked`; the locked copy is republished; a tombstone older than the unlock `updatedAt` stays inert; a newer tombstone (after unlock) deletes. `applyRemoteMerge` must never delete a locked local item or its assets. Tests for all four orderings.
- **4B #10** (Medium-High) `pushSynchronously()`/`pullSynchronously()` return early when sync is disabled or iCloud is unavailable; `ensureCloudDirectories()` never creates the `com~apple~CloudDocs` root, only `Klip/` inside an existing one. Test with a missing cloud root at terminate.
- **4B #7** (Low) enforce snapshot `version` on read (ignore newer versions, log once).
- **5A-08** (High) in the file capture path compute the fingerprint and dedupe **before** copying files (store side `makeFileItem` split into `fingerprint(for:)` then `copyIfNew`; you may reorder the watcher's file-branch calls - that region is yours, the text branch is 5Cb's). Add a launch-time orphan sweep: `files/<uuid>/`, `images/`, `texts/`, `flavors/` entries with no item (and no tombstone-pending sync need) are deleted on a utility queue after load (log counts).
- **5A-09** (High) same-basename files in one copy: uniquify names (`name (2).ext`) instead of failing; the clip keeps all files.
- **5A-13** (Medium) debounce starvation: the 300 ms save debounce must also flush when the last write is older than 2 s (max latency), so a burst of mutations cannot postpone persistence indefinitely; kill -9 at a 10 ms mutation cadence loses at most the last 2 s.
- **Quit-time sync push blocking main up to 20 s per file** (5A medium): bound the terminate push to 3 s total, skip attachments beyond that (they sync next launch).
- Every other Medium/Low in `review-5A.md` whose file is `Services/ClipboardStore.swift`, `Services/SyncMerge.swift`, `Services/CloudDriveSync.swift`, `Models/*`, `Services/PasteboardFlavors.swift`, or the file branch of `ClipboardWatcher.swift` (e.g. dead `.file` dedupe path, destructive image dedupe): fix or justify.

## Verify
`scripts/gate.sh` green; re-run the 4B probe scenarios 3 and 10 (two stores + fake cloud root) and the 5A harness for 5A-02/05/13 (under `scratchpad/harness*` or rebuild small ones); report the measured numbers. Add "Fixed" lines to `CHANGELOG.md` with the finding ids.

Owns: `Services/ClipboardStore.swift`, `Services/SyncMerge.swift`, `Services/CloudDriveSync.swift`, `Services/PasteboardFlavors.swift`, `Models/**`, `Services/ClipboardWatcher.swift` (file branch only), `AppDelegate.swift` (terminate path), `Tests/**` (your suites + `TestRunner.swift` list), `CHANGELOG.md` (Fixed).
Return: table finding-id -> fix -> test -> measurement, gate output, what you did not fix and why, `git status --short`.
