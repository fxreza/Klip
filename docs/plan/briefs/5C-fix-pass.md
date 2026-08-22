# Task 5C - Fix pass from the reviews (Sonnet 5)

WORKTREE: (set at launch). Do NOT commit. Do NOT touch the main checkout. Never write to the user's real `~/Library/Application Support/Buffer` or iCloud Drive (`KLIP_DATA_DIR`/`KLIP_CLOUD_ROOT` temp dirs only).

Read first: `docs/plan/review-4B.md`, `docs/plan/review-5A.md`, `docs/plan/review-2B.md` (the medium item M1 is already fixed on main: RTF cap). Then the code each finding points at.

## Must fix (in this order)
1. **4B #3 - remote tombstone deletes a locked clip** (`Services/SyncMerge.swift`): a tombstone never removes a record whose surviving state has `isLocked == true`. Rule: locked wins over deletion from any device; the locked copy is kept, and the merging device republishes it so the deleting device gets it back (its tombstone stays but is inert against this id while the record is locked; once unlocked, an *older* tombstone must not retroactively delete it - compare tombstone `deletedAt` against the unlock `updatedAt`). Add tests: lock-then-remote-delete keeps; remote-delete-then-lock keeps; unlock after an old tombstone keeps; delete after unlock (newer tombstone) deletes.
2. **4B #10 - quit-time push recreates cloud dirs when iCloud is unavailable** (`Services/CloudDriveSync.swift`, `AppDelegate.applicationWillTerminate`): `pushSynchronously()`/`pullSynchronously()` must return early when `!isAvailable` or sync is disabled, and `ensureCloudDirectories()` must never create the root `com~apple~CloudDocs` folder itself (only `Klip/` inside an existing one). Test: with a missing cloud root, terminate-time push creates nothing.
3. **Every Critical and High in `review-5A.md`**, then the Mediums. For each: fix, add a regression test where the scenario is testable, and note the finding id in the commit-ready summary.
4. **2B low items**: Clear History result alert wording ("kept N protected clips" not "locked"); add the three missing tests (HotkeyRecorder modifier gate can be a pure-function test on the key-name/modifier mapping, folder drag payload with image/file ids, `cycleScope` wraparound).
5. **4B #7**: enforce the snapshot `version` field on read (ignore snapshots with a version greater than what this build knows, log once).

## Do not
Change behavior beyond the findings; restyle; touch docs except `CHANGELOG.md` "Fixed" entries.

## Verify
`scripts/gate.sh` green; re-run the sync probe scenarios 3 and 10 from the 4B report's method (two stores + fake cloud root) and show they pass; list anything from the reviews you deliberately did not fix and why.

Owns: any source/test file the findings point at, `CHANGELOG.md` (Fixed section).
Return: table finding-id -> fix -> test, gate output, `git status --short`.
