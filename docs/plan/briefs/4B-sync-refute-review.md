# Task 4B - Refute-review of iCloud Drive sync (Sonnet 5, read-only + report)

WORKTREE: (set at launch). Do NOT edit any source file. Write exactly one file: `docs/plan/review-4B.md`. NEVER touch the user's real `~/Library/Mobile Documents/com~apple~CloudDocs`; every experiment uses `KLIP_CLOUD_ROOT=<temp dir>` and `KLIP_DATA_DIR=<temp dir>` (plus `KLIP_DEVICE_ID`/`KLIP_DEVICE_NAME`/`KLIP_SYNC_ENABLED=1` env overrides documented in `Services/CloudDriveSync.swift`).

Read first: `docs/plan/briefs/4A-icloud-drive-sync.md` (the design), then `Services/SyncMerge.swift`, `Services/CloudDriveSync.swift`, the Phase 4A regions of `Services/ClipboardStore.swift`, `Tests/SyncMergeTests.swift`, `Tests/CloudDriveSyncTests.swift`, `Views/Settings/SyncTab.swift`. The 4A agent's own "known limitations" list: image dedupe across devices needs a content hash; 20 s timeout abandons the wait not the copy; not-yet-materialised iCloud files are skipped and retried; `syncSkippedLarge` has no badge; tombstone state is behind an `NSLock` shared between main thread and the I/O queue.

## Stance
Try to break it. For each scenario run it for real with two instances or two stores + a fake cloud root (the unit tests show how), or trace the code path precisely, and record PASS / FAIL (with a reproducible sequence) / NOT TESTABLE (why).

## Scenarios (all)
1. Concurrent adds on A and B, then both pull: both converge, no duplicates, no lost clip, order stable.
2. Same text copied on both within seconds: content dedupe keeps one; flags/tags unioned; the *older* survives.
3. Lock on A vs delete on B (both before the other pulls): which wins, is the lock honored? A locked clip must never be deleted by a remote tombstone unless... (state the rule the code implements and whether it matches "locked clips can't be deleted until unlocked"; flag as a design question if the implementation deletes a locked clip via a tombstone from another device).
4. Edit text on A and pin on B concurrently: whole-record newest-wins loses one change - document which; is that acceptable or should flags merge field-wise?
5. Eviction on A (small history cap) must not delete on B and must not resurrect on A; sync-ignore expiry at 30 days.
6. Folder rename on A vs delete on B; items in the deleted folder keep lock, lose folderID.
7. Corrupt or truncated remote `history.json` / `tombstones.json`: ignored with a log, no crash, no data loss; a remote file with a future schema version.
8. Attachment above the cap: skipped upload, flag set, other device shows a reference/missing state rather than crashing; attachment missing on disk locally.
9. Disable sync on A then re-enable: no duplicate device dirs, full reconcile; "Remove this device's cloud copy" removes only `devices/<id>/`; the typed-confirm "remove all" removes `Klip/`.
10. iCloud unavailable (cloud root missing) at launch with sync enabled: app launches, status explains, no retries storm (check timer/poll cadence and log spam).
11. Quit during a push (kill -9 the instance mid-write): `NSFileCoordinator` + atomic write leave a valid previous file.
12. Main-thread hangs: any cloud I/O on the main actor? Pull of a 5,000-item snapshot - time it.
13. Thread safety: the `NSLock`-guarded tombstone state and the `applyRemoteMerge` guard flag - any race that could push the pre-merge state and drop remote changes?
14. The `KLIP_SYNC_ENABLED`/device-id env overrides cannot affect a normal launch (no env) - confirm.
15. Privacy: nothing other than the user's own iCloud Drive is written; no network calls.

## Output
`docs/plan/review-4B.md`: table (scenario, verdict, evidence/repro, severity, suggested fix), then "fix before release" list. Return the table in your final message.
