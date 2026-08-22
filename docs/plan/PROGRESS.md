# Progress log (autonomous run started 2026-08-22 ~02:30 local)

Read this first if you are resuming as the manager. Plan: `PLAN.md`. Briefs: `briefs/`. Analysis: `../analysis/`.

## Ground rules in force
- Worktrees are created manually: `git worktree add -b task/<id> <scratchpad>/wt/<id> refs/heads/main` + symlink `reference`. Agents get the absolute worktree path, never commit; I commit on the task branch, `git merge --no-ff`, run `scripts/gate.sh` (build + tests, strict), push `refs/heads/main:refs/heads/main` (upstream has a `main` *tag*, so always use explicit refspecs), remove the worktree.
- Test instances: `scripts/run_app.sh` (own `KLIP_DATA_DIR`, `KLIP_DEBUG=1`, Darwin hooks `com.fxreza.klip.debug.show|hide|toggle|quit`). The user's live data in `~/Library/Application Support/Buffer` is never touched.
- The Mac screen is locked while the user is away: `screencapture` is useless; visual checks use offscreen `NSHostingView` + `cacheDisplay` harnesses in the scratchpad (proven by 1A, 3E, 3G).
- Commits use the GitHub noreply identity (repo-local git config). Signing: "QTranslate Dev".
- Build flag `-default-isolation MainActor` is required (scripts + build_dmg.sh have it). Baseline warning count: 14 (upstream actor warnings + one `isFile` isolation warning). Do not try `nonisolated` on the model structs (raises warnings to 32).

## Timeline
| When | What | Tag |
|---|---|---|
| Phase 0 | 0.2 build_local.sh/run_app.sh (Haiku), 0.3 swiftc test runner (Sonnet), 0.4 Klip rebrand + data-dir override + Buffer migration + debug hooks (Sonnet), 0.5 upstream baseline build in `releases/v2.5.0-upstream/` | `v3.0.0-phase0` |
| Phase 1 | 1A HistoryWindow split -> `Views/History/*` + `HistoryViewModel` + `FilterState` (Opus); 1B model/store: `isLocked`, `folderID`, `kind`, `FileAttachment`, `Folder`, v2 schema, atomic+debounced saves, `HistoryLimit` k1/k5/k10/unlimited with cap on unprotected items only (Opus); 1C `SettingsManager` ObservableObject, `Views/Theme/*`, `FontScale`, tabbed Settings (Sonnet). Integration removed shims, `gate.sh` added. 56 tests. | `v3.0.0-alpha1` |
| Phase 3 early | 3E part 1 shortcuts model/manager/recorder/Settings tab (Sonnet) - 70 tests; 3G permissions/onboarding/toast (Sonnet) - 76; 3C ContentDetector + capture-time kind + backfill (Sonnet) - 90. All merged to main. | - |
| Phase 2 | 2A Clipfield UI shell (Opus): sidebar/chips/rows/preview/prompts, 11 offscreen renders, 70/70 view-model behaviors; merged clean; `.file` case added; 99 tests | `v3.0.0-alpha2` |
| Phase 3 wave 1 | 3A lock UX (Sonnet), 3B folders + drag/drop (Opus), 3F file clips + QuickLook (Sonnet), 3E part 2 monitor wiring (Sonnet) - RUNNING in parallel worktrees | - |
| Phase 3 wave 2 | 3D context menu + rich capture + plain paste, 3H font sweep (Haiku), 3C part 2 search upgrade - briefs written, start after wave 1 merges; then 2B refute-review -> `v3.0.0-beta1` | - |

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

## Remaining
2A -> 3A lock UX, 3B folders + drag/drop (Opus), 3D row context menu + rich capture + plain paste, 3F file clips + QuickLook, 3E part 2 (monitor wiring + legend), 3H font sweep (Haiku), 3C part 2 search upgrade -> `v3.0.0-beta1` -> 4A iCloud Drive sync (Opus) + 4B review -> 5A review (Opus), 5B pbxproj, 5C fixes, 5D docs (Haiku), 5E release + install.
