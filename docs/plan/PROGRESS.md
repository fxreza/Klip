# Progress log (autonomous run started 2026-08-22 ~02:30 local)

Read this first if you are resuming as the manager. Plan: `PLAN.md`. Briefs: `briefs/`. Analysis: `../analysis/`.

## Ground rules in force
- Worktrees are created manually: `git worktree add -b task/<id> <scratchpad>/wt/<id> refs/heads/main` + symlink `reference`. Agents get the absolute worktree path, never commit; I commit on the task branch, `git merge --no-ff`, run `scripts/gate.sh` (build + tests, strict), push `refs/heads/main:refs/heads/main` (upstream has a `main` *tag*, so always use explicit refspecs), remove the worktree.
- Test instances: `scripts/run_app.sh` (own `KLIP_DATA_DIR`, `KLIP_DEBUG=1`, Darwin hooks `com.fxreza.klip.debug.show|hide|toggle|quit`). The user's live data in `~/Library/Application Support/Buffer` is never touched.
- The Mac screen is locked while the user is away: `screencapture` is useless; visual checks use offscreen `NSHostingView` + `cacheDisplay` harnesses in the scratchpad (proven by 1A, 3E, 3G).
- Merge with `scripts/merge_task.sh <id> "<msg>"` (commits the worktree, merges, exit-checked gate, re-syncs pbxproj, pushes only on success). Never pipe `gate.sh` into `tail` in a `&&` chain - that pushed a broken build twice.
- Commits use the GitHub noreply identity (repo-local git config). Signing: "QTranslate Dev".
- Build flag `-default-isolation MainActor` is required (scripts + build_dmg.sh have it). Baseline warning count: 14 (upstream actor warnings + one `isFile` isolation warning). Do not try `nonisolated` on the model structs (raises warnings to 32).

## Timeline
| When | What | Tag |
|---|---|---|
| Phase 0 | 0.2 build_local.sh/run_app.sh (Haiku), 0.3 swiftc test runner (Sonnet), 0.4 Klip rebrand + data-dir override + Buffer migration + debug hooks (Sonnet), 0.5 upstream baseline build in `releases/v2.5.0-upstream/` | `v3.0.0-phase0` |
| Phase 1 | 1A HistoryWindow split -> `Views/History/*` + `HistoryViewModel` + `FilterState` (Opus); 1B model/store: `isLocked`, `folderID`, `kind`, `FileAttachment`, `Folder`, v2 schema, atomic+debounced saves, `HistoryLimit` k1/k5/k10/unlimited with cap on unprotected items only (Opus); 1C `SettingsManager` ObservableObject, `Views/Theme/*`, `FontScale`, tabbed Settings (Sonnet). Integration removed shims, `gate.sh` added. 56 tests. | `v3.0.0-alpha1` |
| Phase 3 early | 3E part 1 shortcuts model/manager/recorder/Settings tab (Sonnet) - 70 tests; 3G permissions/onboarding/toast (Sonnet) - 76; 3C ContentDetector + capture-time kind + backfill (Sonnet) - 90. All merged to main. | - |
| Phase 2 | 2A Clipfield UI shell (Opus): sidebar/chips/rows/preview/prompts, 11 offscreen renders, 70/70 view-model behaviors; merged clean; `.file` case added; 99 tests | `v3.0.0-alpha2` |
| Phase 3 | merged: 3A lock UX (109 tests), 5B xcodeproj sync script (+ quoting fix for `+` in names), 3E part 2 table-driven monitor + live legend (115), 3H font sweep, 3C part 2 search upgrade (124, 24 ms/10k items). 3B folders + drag/drop (Opus, 152), 3F file clips + QuickLook (Sonnet, 167). 3D rich/plain + context menu (183), 2B refute-review: NO regressions, 1 medium (RTF cap) -> `docs/plan/review-2B.md`; 4A iCloud Drive sync (Opus, 215 tests). | `v3.0.0-beta1` |
| Phase 5 | 5D docs merged (README/ATTRIBUTION/CHANGELOG/SECURITY/RELEASE, version 3.0.0 build 8). The user's usage limit interrupted 4B and 5A at their start; both relaunched after the reset. 4B sync review (2 fails) and 5A adversarial review (12 critical/high, 18 medium/low) -> `review-4B.md`, `review-5A.md`. 5Ca fix pass merged (240 tests: eviction stall 162 s -> 1.3 ms, per-record decode, sync lock-wins, guarded quit push, dedupe-before-copy, orphan sweep, debounce max delay). `build_local.sh`/`build_dmg.sh` gained an iconutil fallback (actool needs Xcode). 5Cb merged (269 tests: key monitor scoped to the panel, capture off main 5 s -> 4 ms, thumbnail cache, copy-then-swap installer with identity check, search cache). The "Klip Update Failed" popups the user saw came from 5Cb exercising the updater install script; nothing was installed. NEXT: 5C fixes from the three reports, 5E release (`scripts/release.sh`), install + trash Buffer.app, GitHub release `klip-v3.0.0`. | | - |

## Decisions made on the fly (all consistent with the approved D-table)
- `mailto:` links classify as `.email` (Clipfield does the same).
- Glyph order for shortcut display is ⌃⌥⇧⌘ (macOS standard).
- History cap counts non-protected items only; protected items never evicted; the just-copied clip is never dropped.
- `clear(keepProtected: Bool)`: even `keepProtected: false` keeps locked items.
- 1A: stable pinned-first partition replaces the invalid sort predicate.

## Known open items
- `Klip.xcodeproj/project.pbxproj` is out of date (new files not listed) - task 5B.
- Upstream `/Applications/Buffer.app` was running at session start but is not running any more (not killed by our scripts - they only target `build/Klip.app`); report to the user.
- README / CHANGELOG / ATTRIBUTION - task 5D. "Star on GitHub"/"Report an Issue" links in Settings still point at upstream (intentional attribution for now).
- Accessibility for the final Klip build must be granted by the user on return.

## Shipped 2026-08-22
- `klip-v3.0.0` tagged; `releases/v3.0.0/Klip_Universal.zip` + checksums; `dist/Klip.app`; GitHub release https://github.com/fxreza/Klip/releases/tag/klip-v3.0.0
- Installed `/Applications/Klip.app` (signed QTranslate Dev, universal), launched; upstream `Buffer.app` moved to Trash; Buffer data backed up to `releases/backup-20260822-091610/` (gitignored) and left untouched in `~/Library/Application Support/Buffer`.
- User still has to grant Accessibility to Klip (Permissions… in the menu bar) for auto-paste.

## 3.0.1 (2026-08-22, after the user's first live test)
- Fixed: `QLPreviewView` abort when a file clip was selected / window opened with one selected (3 crash reports) - previews are QuickLook thumbnails now, gate refuses the symbol; ⌘F = favorite; "star" -> "favorite" wording; scope cycling removed; Paste button removed; legend shows ↩ paste / ⌥↩ paste plain; preview pane full height; scroll-to-selection reliable; no blink on key navigation; OCR copy button works with a toast. 275 tests.
- Installed over 3.0.0; release https://github.com/fxreza/Klip/releases/tag/klip-v3.0.1. Build/dist dirs use `.noindex` (Spotlight duplicates), see AGENTS.md.
- Open question from the user: BTT ⌘E - Klip only registers ⇧⌘V globally; in-window keys are panel-scoped.

## 3.0.2 (2026-08-22)
- Tags chip (shows tagged clips + a tag bar), "# tags" legend hint, legend wraps to two rows at the default width, Settings footer without GitHub/issue links. 294 tests. Release https://github.com/fxreza/Klip/releases/tag/klip-v3.0.2, installed.
- Dev safety: test instances (`KLIP_DATA_DIR`) now use the `com.fxreza.klip.test` defaults suite after an agent harness flipped two real preferences (restored).
- Edit shortcut vs BTT ⌘E: user can rebind Edit in Settings > Shortcuts or scope the BTT trigger; no app change.

## 3.0.3 (2026-08-22)
- Images keep their original bytes/format (JPEG/PNG/HEIC/GIF/WebP) on capture, paste (original UTI first + TIFF fallback), save and sync; TIFF-only clipboards still convert to PNG. `imageUTI` field. 303 tests. https://github.com/fxreza/Klip/releases/tag/klip-v3.0.3, installed.

## 3.0.4 (2026-08-22)
- Fix: PNG screenshots were stored as JPEG because the pasteboard server translates undeclared types on demand; only declared formats are accepted now, in declaration order. 304 tests. https://github.com/fxreza/Klip/releases/tag/klip-v3.0.4, installed.

## Remaining (post-release)
2A -> 3A lock UX, 3B folders + drag/drop (Opus), 3D row context menu + rich capture + plain paste, 3F file clips + QuickLook, 3E part 2 (monitor wiring + legend), 3H font sweep (Haiku), 3C part 2 search upgrade -> `v3.0.0-beta1` -> 4A iCloud Drive sync (Opus) + 4B review -> 5A review (Opus), 5B pbxproj, 5C fixes, 5D docs (Haiku), 5E release + install.
