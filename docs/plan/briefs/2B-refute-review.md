# Task 2B - Refute-review of the rebuilt UI against the preservation checklist (Sonnet 5, read-only + fix list)

WORKTREE: (set at launch, after Phase 3 merged). Do NOT edit any source file. You may build, run harnesses in the scratchpad, and write ONE report file: `docs/plan/review-2B.md`.

Read first: `docs/plan/PLAN.md` §7 (the 12-item preservation checklist) and §6, `docs/plan/PROGRESS.md`, `docs/analysis/buffer.md` §3 (feature inventory with the original behaviors), then the code under `Views/History/**`, `Services/PasteController.swift`, `Services/ClipboardWatcher.swift`, `Services/ClipboardStore.swift`. The 2A harnesses in `/private/tmp/claude-501/-Users-sam-Claude-Code-clipboard-manager/3854505a-128a-45e2-b039-51ef49965b3a/scratchpad/harness/` (`RenderHarness.swift`, `render.sh`, `BehaviorHarness.swift`, `behavior.sh`) are yours to reuse/extend.

## Stance
You are trying to PROVE that an existing Buffer behavior was lost or changed. Default to "REGRESSED" unless you can point at the code path that preserves it. For each checklist item and each feature in `docs/analysis/buffer.md` §3, write: VERIFIED (how: harness test / code trace) | REGRESSED (scenario) | CHANGED-BY-DESIGN (cite the PLAN decision) | UNVERIFIABLE (why - e.g. needs a real mouse/screen).

## Must cover explicitly
- Single click selects only; double-click copies + closes; nothing pastes on click; ⌘-click/⇧-click/⇧↑↓; Enter pastes single or multiple; PasteButton.
- Search debounce 200 ms, 90 s persistence, selection restore; `#tag` mode; ⌫ clears tag filter only when search is empty; Tab completion.
- Pin/star/edit/tag/save/OCR/delete through keys, preview buttons and context menu; edit-mode auto-exit and clipboard update on exit; large-text chunking and full paste.
- Lock: every deletion path (key, context menu, preview trash, multi-select confirm, Clear History, eviction, folder delete) skips locked clips; folder move locks; unlock then delete works.
- Folders: create/rename/delete (3 branches), move via prompt and context menu, drag payload; scope switching ⌘[ ⌘]; counts.
- Chips and scopes combine correctly with search and tags; Favorites scope = starred.
- Custom shortcuts: every default binding dispatches; rebinding works; fixed keys unchanged; legend updates.
- Files: capture of a non-image file, paste writes URLs, Save to Disk, Save All, QuickLook fallback when a file is missing.
- Rich text: rich paste replays flavors, plain paste strips, "always plain" setting, edit drops RTF.
- Window: borderless panel opens under the mouse, size persisted, click-outside closes, Esc chain, `previousApp` reactivation before paste, Accessibility toast when untrusted.
- Status bar: menu items (Settings, Permissions, Check for Updates, Pause/Resume, Clear History, Quit), hide icon setting.
- Existing v2.5.0 `history.json` loads (copy the user's real file from `~/Library/Application Support/Buffer/history.json` into a temp `KLIP_DATA_DIR` - read-only on the original - and confirm item count and flags survive and re-save as v2).

## Output
`docs/plan/review-2B.md`: table (area, verdict, evidence or scenario, severity, suggested fix). Then a short list "fix before beta1" (Critical/High) and "fix before release" (Medium). Return the table in your final message as well.
