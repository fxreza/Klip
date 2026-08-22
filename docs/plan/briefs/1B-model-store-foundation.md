# Task 1B - Model and store foundation (Opus 5)

WORKTREE: (set at launch). Use absolute paths under it. Do NOT commit. Do NOT touch the main checkout.

Read first: `docs/analysis/buffer.md` sections 2, 3, 6 (change maps A, B, C, E), `docs/analysis/clipfield.md` section 4 (Folder model), `docs/analysis/pesty.md` bonus section; then `Models/ClipboardItem.swift`, `Services/ClipboardStore.swift`, `Services/ClipboardWatcher.swift`, `Services/SettingsManager.swift`, `Tests/TestRunner.swift`.

## Goal
Add the data foundation for folders, locks, file clips, content kinds and a real history limit - with migration-free loading of existing `history.json` files - plus hardened persistence. UI for these features comes in later phases; nothing user-visible changes in this task except the history-limit presets.

## 1. `Models/ClipboardItem.swift`
Add fields (all optional / defaulted, decoded with `decodeIfPresent`, so v2.5.0 files load unchanged):
- `var isLocked: Bool = false`
- `var folderID: UUID? = nil`
- `var kind: ContentKind? = nil` (nil = not yet detected; detection is Phase 3C)
- `var fileAttachment: FileAttachment? = nil`
- `var rtfFilename: String? = nil`, `var flavorsFilename: String? = nil` (reserved for Phase 3D rich capture - fields only)
- `var isProtected: Bool { isPinned || isBookmarked || !tags.isEmpty || isLocked || folderID != nil }` (protected from **eviction**). Only `isLocked` blocks **deletion**.
- Remove the dead `truncatedText` factory and `isTruncated` / `originalSizeBytes` fields (keep decoding tolerant: unknown keys are ignored by JSONDecoder anyway).
- **Do NOT add `case file` to `ClipboardItemType` yet** - it would break exhaustive switches in view files another agent is splitting right now. Instead add `var isFile: Bool { fileAttachment != nil }`; the enum case is added at integration.
- `previewText`: if `fileAttachment != nil` return its `originalName` (+ " +N" when `additionalNames` non-empty).

New files:
- `Models/ContentKind.swift`: `enum ContentKind: String, Codable, CaseIterable { case text, richText, link, image, file, color, code, email, phone }` with `label` and `systemImage` (SF Symbols: doc.text, doc.richtext, link, photo, doc, paintpalette, chevron.left.forwardslash.chevron.right, envelope, phone).
- `Models/FileAttachment.swift`: `struct FileAttachment: Codable, Equatable { var originalName: String; var additionalNames: [String] = []; var storedRelativePath: String?  /* under files/<uuid>/ when copied */; var referencePath: String? /* original path when not copied */; var bookmark: Data? /* security-scoped bookmark for referencePath */; var uti: String?; var byteSize: Int64; var isReference: Bool { storedRelativePath == nil } }`.
- `Models/Folder.swift`: `struct Folder: Identifiable, Codable, Equatable { let id: UUID; var name: String; let createdAt: Date; var sortIndex: Int }`.

## 2. `Services/SettingsManager.swift` - history limit ONLY (another agent owns the rest of this file; touch nothing else in it)
Replace `HistoryLimit` with:
```swift
enum HistoryLimit: Int, CaseIterable {
    case k1 = 1000, k5 = 5000, k10 = 10000, unlimited = 0
    static let `default`: HistoryLimit = .k10
    var maxItems: Int? { self == .unlimited ? nil : rawValue }
    var isUnlimited: Bool { self == .unlimited }
    var label: String   // "1,000", "5,000", "10,000", "Unlimited"
    var subtitle: String
    /// Maps legacy stored values (100, 500, 1000 from Buffer 2.x) and any unknown value.
    static func from(storedRaw: Int?) -> HistoryLimit  // nil/absent -> .default; 100/500/1000 -> .k1; 5000 -> .k5; 10000 -> .k10; 0 -> .unlimited; else .default
}
```
Keep the UserDefaults key `historyLimit` and the `.bufferHistoryLimitChanged` notification. The settings UI (picker using `HistoryLimit.allCases`, `.label`, `.subtitle`) is done by the other agent against exactly this API.

## 3. `Services/ClipboardStore.swift`
Persistence:
- `history.json` becomes `{"version": 2, "items": [...]}`. Loader accepts both the bare array (v1) and the wrapper. `folders.json` = `{"version": 1, "folders": [...]}`.
- Writes: `Data.write(to:options:.atomic)`. Replace per-mutation synchronous rewrites with a **300 ms debounced** save on `saveQueue`; add `func flushPendingSave()` and call it from `AppDelegate.applicationWillTerminate` (add that one line; if the method does not exist, add it). Any public mutation still results in a save; tests can call `flushPendingSave()` then read the file.
- Decode failure: rename the bad file to `history.corrupt-<yyyyMMdd-HHmmss>.json`, log, start empty (never silently overwrite a file that failed to decode).
- New dirs: `files/` (for Phase 3F), `flavors/` (Phase 3D); `deleteAssociatedFiles` must also remove `files/<uuid>/`, `flavors/<uuid>.plist`, `<uuid>.rtf` when present. `itemSize` accounts for `fileAttachment.byteSize`.
- Keep the storage-root logic added by task 0.4 (`KLIP_DATA_DIR` override, migration from Buffer) intact.

Eviction / limit:
- `maxItems` -> `SettingsManager.shared.historyLimit.maxItems` (nil = unlimited -> never evict).
- Eviction evicts the **oldest non-protected** item (use `isProtected`). If nothing is evictable, **do not evict anything** (today it deletes a protected item - that is now wrong because locked items must never vanish). `handleLimitChanged` same rule.
- Remove the dead `moveToTop`.

Lock / delete API (source-compatible with existing callers: keep names, add `@discardableResult` return values):
- `func toggleLock(_ item: ClipboardItem)`, `func setLocked(ids: Set<UUID>, locked: Bool)`
- `@discardableResult func delete(_ item: ClipboardItem) -> Bool` (false + no-op when locked)
- `struct DeleteResult { let deleted: Int; let skippedLocked: Int }`, `@discardableResult func delete(_ items: [ClipboardItem]) -> DeleteResult`
- `clear()` keeps protected items (it already keeps pinned/bookmarked/tagged; now also locked and foldered); add `@discardableResult func clear() -> DeleteResult`.

Folders API:
- `@Published private(set) var folders: [Folder]` (sorted by `sortIndex`)
- `@discardableResult func createFolder(name: String) -> Folder` (trim; empty -> "Untitled Folder"; duplicate names allowed)
- `func renameFolder(id: UUID, to name: String)`
- `enum FolderDeleteMode { case moveItemsOut, deleteItems(includeLocked: Bool) }`, `struct FolderDeleteResult { let folderDeleted: Bool; let movedOut: Int; let deleted: Int; let skippedLocked: Int }`, `@discardableResult func deleteFolder(id: UUID, mode: FolderDeleteMode) -> FolderDeleteResult`. `deleteItems(includeLocked: false)` leaves locked items in the folder and does NOT delete the folder (folderDeleted false) - the UI will ask for explicit confirmation and call again with `includeLocked: true`.
- `func moveItems(ids: Set<UUID>, toFolder folderID: UUID?)` - when `folderID != nil` also sets `isLocked = true` (folder clips are locked by default); moving out (`nil`) leaves `isLocked` unchanged.
- `func items(inFolder id: UUID) -> [ClipboardItem]`, `func folderCounts() -> [UUID: Int]`.
- `func reorderFolders(_ ids: [UUID])`.

## 4. `Services/ClipboardWatcher.swift`
No functional change. Only: where items are created, nothing new is required (kind detection is 3C). Do not touch.

## 5. Tests (`Tests/ClipboardStoreTests.swift`, `Tests/FolderTests.swift`, extend `Tests/ClipboardItemTests.swift`)
Use `setenv("KLIP_DATA_DIR", tempDir.path, 1)` inside `withTempDir` before constructing `ClipboardStore()` (it reads the env in init), call `flushPendingSave()` before inspecting files. Cover: v1 bare-array `history.json` loads and is re-saved as v2; v2 round trip with every new field; corrupt file is renamed not overwritten; eviction respects `maxItems` and never evicts protected items; unlimited never evicts; `delete` refuses locked; `delete([...])` reports skippedLocked; `clear` keeps locked/foldered; folder create/rename/delete in all three modes; `moveItems` locks; `folderCounts`; `HistoryLimit.from(storedRaw:)` mapping table. Register the suites in `TestRunner.swift`'s suite list (that is the only edit allowed there).

## Verify
`scripts/build_local.sh` zero errors, no new warnings; `scripts/run_tests.sh` all pass. Also run `scripts/run_app.sh`, copy something (`pbcopy`), `notifyutil -p com.fxreza.klip.debug.quit`, then confirm `build/test-data/history.json` is the v2 wrapper and `folders.json` exists. Remove `build/`.

Owns: `Models/**`, `Services/ClipboardStore.swift`, `Services/SettingsManager.swift` (the `HistoryLimit` enum and the `historyLimit` load/save lines ONLY), `AppDelegate.swift` (the single `flushPendingSave()` call ONLY), `Tests/ClipboardStoreTests.swift`, `Tests/FolderTests.swift`, `Tests/ClipboardItemTests.swift`, `Tests/TestRunner.swift` (suite list only).
Return: summary, public API listing (signatures) for the integration step, test output, `git status --short`.
