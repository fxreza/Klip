# Task 5B - Keep Klip.xcodeproj in sync with the source tree (Sonnet 5)

WORKTREE: (set at launch). Do NOT commit. Do NOT touch the main checkout. Do NOT edit any `.swift` file.

Context: there is no Xcode.app on this Mac; the canonical build is `scripts/build_local.sh` / `build_dmg.sh` (they glob sources). `Klip.xcodeproj/project.pbxproj` still lists the v2.5.0 files (including the deleted `Views/HistoryWindow.swift`, `Views/ClipboardListView.swift`, `Views/ClipboardItemRow.swift`, `Views/SearchField.swift`) and none of the ~40 new files under `Models/`, `Services/`, `Views/History/`, `Views/Theme/`, `Views/Settings/`, `Views/Permissions/`. Read `docs/analysis/buffer.md` §1 (pbxproj structure: `PBXBuildFile` list lines ~9-31, `PBXFileReference` ~44-68, `PBXGroup` children, `PBXSourcesBuildPhase` ~230-260) and the current `project.pbxproj`.

## Deliverables
1. `scripts/sync_xcodeproj.py` (Python 3, stdlib only): parses `Klip.xcodeproj/project.pbxproj` textually (the old-style plist format), and for the app target:
   - removes `PBXBuildFile`/`PBXFileReference`/group entries for `.swift` files that no longer exist on disk;
   - adds entries for every `.swift` file found by `find Models Services Views -name '*.swift'` plus root `*.swift` (excluding `Tests/`, `BufferTests/`, `reference/`, `build/`, `scripts/`) that is not yet referenced: a `PBXFileReference` (`lastKnownFileType = sourcecode.swift`, `path` relative to its group, `sourceTree = "<group>"`), a `PBXBuildFile`, membership in the matching `PBXGroup` (create nested groups for `Views/History`, `Views/Theme`, `Views/Settings`, `Views/Permissions` mirroring the folders), and the `PBXSourcesBuildPhase` `files` list of the **app** target only;
   - generates stable 24-hex-char object ids (e.g. md5 of the path, uppercased, truncated) so re-running is idempotent and diffs stay small;
   - adds the frameworks the build scripts link beyond Cocoa: `SwiftUI`, `Carbon`, `Vision`, `Quartz`, `QuickLookThumbnailing` as weak/implicit is fine - if adding `PBXFrameworksBuildPhase` entries is too fiddly, instead add `OTHER_LDFLAGS = "-framework Quartz -framework QuickLookThumbnailing"` to both app build configurations and say so;
   - adds `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;` to both app configurations and the test target configurations (that is the Xcode equivalent of `-default-isolation MainActor`);
   - `--check` mode exits 1 and lists differences without writing (for CI);
   - prints a summary of added/removed entries.
2. Run it; verify with `plutil -lint Klip.xcodeproj/project.pbxproj` (must pass) and a second `--check` run (must be clean). Also make sure every path it references exists (`python3 -c` over the file refs).
3. Update the test target: the old `BufferTests/ClipboardItemTests.swift` stays (XCTest, for Xcode users); do not add `Tests/` (swiftc runner) to the Xcode project.
4. Add a short section to `RELEASE.md` ("Keeping the Xcode project in sync: run `python3 scripts/sync_xcodeproj.py` after adding files; CI-style check: `--check`").

Owns: `scripts/sync_xcodeproj.py`, `Klip.xcodeproj/project.pbxproj`, `RELEASE.md` (one section).
Return: summary of entries added/removed, lint output, `git status --short`.
