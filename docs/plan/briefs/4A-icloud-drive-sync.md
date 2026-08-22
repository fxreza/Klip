# Task 4A - iCloud Drive file sync (Opus 5)

WORKTREE: (set at launch). Do NOT commit. Do NOT touch the main checkout.

Read first: `docs/plan/PLAN.md` (D7, Phase 4 row), `docs/analysis/pesty.md` (executive summary: the iCloud Drive approach and its weaknesses), then Pesty's code for the approach: `reference/pesty/Sources/Pesty/Store/ClipboardStore.swift` lines 50-78 and 656-744, `reference/pesty/Sources/Pesty/AppController.swift:226-237`. Then ours: `Services/ClipboardStore.swift` (v2 schema, folders, `flushPendingSave`, attachments dirs), `Models/*`, `Services/SettingsManager.swift`, `Views/Settings/*`, `Services/PermissionsState.swift` (from 3G).

## Design (decided - do not relocate the store like Pesty does)
The local store at `~/Library/Application Support/Klip` stays authoritative. A new `Services/CloudDriveSync.swift` **mirrors** it to `~/Library/Mobile Documents/com~apple~CloudDocs/Klip/`:
```
Klip/
  devices/<deviceID>/history.json      {"version":1,"device":{"id","name","lastPush"},"items":[...full merged item list of that device...]}
  devices/<deviceID>/folders.json      {"version":1,"folders":[...]}
  devices/<deviceID>/tombstones.json   {"version":1,"deleted":[{"id","deletedAt"}],"deletedFolders":[{"id","deletedAt"}]}
  images/<uuid>.png  texts/<uuid>.txt|.rtf  files/<uuid>/<name>  flavors/<uuid>.plist      (write-once by uuid -> no conflicts)
```
- `deviceID`: stable UUID in UserDefaults `sync.deviceID`; `deviceName` = `Host.current().localizedName`.
- Add `var updatedAt: Date` to `ClipboardItem` (default = `timestamp`, decodeIfPresent) and to `Folder` (default = `createdAt`); bump it in every store mutation (pin/star/lock/tags/edit/folder move/rename). Add `var syncSkippedLarge: Bool = false` on `FileAttachment`.
- **Push** (debounced 2 s after any local save, plus on enable and "Sync now"): write this device's three files atomically via `NSFileCoordinator`; copy any attachment not yet present in the cloud dirs (skip attachments above `sync.maxAttachmentMB`, mark `syncSkippedLarge`).
- **Pull** (on start, on directory change, and every 60 s as a fallback): read every *other* device's files; merge into the local store with `SyncMerge` (pure, testable):
  - identity by `id`; for the same id newest `updatedAt` wins whole-record, tags = union;
  - items from other devices whose `contentHash` equals a local item's hash (different ids) are deduped: keep the older one, union flags/tags, keep folderID if either has one;
  - a tombstone (any device) newer than the item's `updatedAt` deletes it locally (and its attachments); tombstones older than 30 days are pruned on push;
  - folders: same newest-wins rule; `deletedFolders` tombstones; items pointing at a deleted folder keep their lock and get `folderID = nil`;
  - items the local device **evicted** by the history cap must not resurrect: keep a local `sync-ignore.json` (id + date, pruned at 30 days) written by the store's eviction path; evictions never write tombstones (so other devices keep their copies) - explicit deletes do;
  - copy attachments for newly arrived items from the cloud dirs into the local dirs (reads of not-yet-downloaded iCloud files may block: do all cloud I/O on a background queue, per-file timeout 20 s, retry next cycle, never block the main thread);
  - apply the merged result to the store on the main actor through a new `ClipboardStore.applyRemoteMerge(_:)` that does not trigger a push loop (guard flag).
- Watching: `DispatchSource.makeFileSystemObjectSource` on `Klip/devices` (and each device dir) + the 60 s poll comparing file modification dates. No CloudKit, no entitlements, no `NSMetadataQuery` ubiquity scopes (they need entitlements).
- Availability: `FileManager.default.fileExists(atPath: "~/Library/Mobile Documents/com~apple~CloudDocs")`; if absent the toggle is disabled with "Sign in to iCloud and enable iCloud Drive in System Settings".
- Disable: stop watching; optional "Remove this device's cloud copy" deletes only `devices/<deviceID>/` (attachments stay because other devices may reference them; offer "Remove all Klip cloud data" behind a typed-confirm sheet that deletes the whole `Klip/` folder).

## Settings (`Views/Settings/SyncTab.swift`) and status
Sync tab: toggle + availability reason, status line ("Last push 2 min ago · last pull 1 min ago · 2 devices: MacBook, Studio"), "Sync now", attachment size cap picker (1/5/10/50/100/500 MB/Unlimited + custom), device name field, disable/remove buttons. Keys: `sync.enabled` (default false), `sync.maxAttachmentMB` (default 50, 0 = unlimited), `sync.deviceID`, `sync.deviceName`, `sync.lastPush`, `sync.lastPull`. Permissions tab (3G): add an "iCloud Drive" row using the same availability check.

## Tests
`Tests/SyncMergeTests.swift`: every merge rule above as pure-function tests. `Tests/CloudDriveSyncTests.swift`: two `ClipboardStore`s in two temp `KLIP_DATA_DIR`s and a temp fake cloud root (inject the root via `CloudDriveSync(cloudRoot:)`), exercise: add on A -> push -> pull on B -> present; lock/tag on B -> A gets it; delete on A -> tombstone -> gone on B; evict on A -> stays on B and does not come back to A; large attachment skipped; corrupt remote file ignored with a logged warning; disabling stops changes.

## Verify
`scripts/build_local.sh`, `scripts/run_tests.sh` all green. Run the test instance with `KLIP_DATA_DIR` and `KLIP_CLOUD_ROOT=<temp dir>` (add that env override next to `KLIP_DATA_DIR` so manual tests never touch the user's real iCloud Drive), enable sync in the Sync tab, copy a clip, confirm the device files appear in the temp cloud root, then a second instance with another `KLIP_DATA_DIR` and the same `KLIP_CLOUD_ROOT` pulls it (you may run two instances; hotkeys are irrelevant, use the debug notifications with a `KLIP_DEBUG_SUFFIX` env if both would collide - add it if needed). Screenshots of the Sync tab. Kill instances, remove `build/`.

Owns: `Services/CloudDriveSync.swift`, `Services/SyncMerge.swift`, `Services/ClipboardStore.swift` (`updatedAt` bumps, `applyRemoteMerge`, eviction -> sync-ignore hook, `KLIP_CLOUD_ROOT`), `Models/ClipboardItem.swift` + `Models/Folder.swift` + `Models/FileAttachment.swift` (new fields only), `Services/SettingsManager.swift` (sync keys only), `Views/Settings/SyncTab.swift`, `Views/Settings/SettingsView.swift` (add the tab only), `Views/Permissions/*` (iCloud row only), `AppDelegate.swift` (start/stop sync), `Tests/SyncMergeTests.swift`, `Tests/CloudDriveSyncTests.swift`, `Tests/TestRunner.swift` (suite list).
Return: summary, the merge rules as implemented, test output, screenshots, known limitations, `git status --short`.
