# Task 5A - Adversarial review of the whole fork (Opus 5, read-only)

WORKTREE: (set at launch). Do NOT edit or commit anything except the report file named below. You may build and run harnesses in the scratchpad.

Read first: `docs/plan/PLAN.md` (sections 2 decisions, 6 traceability, 7 preservation checklist), `docs/plan/PROGRESS.md`, `docs/analysis/buffer.md` §6 risks, then the full diff `git diff baseline-v2.5.0..HEAD --stat` and the code.

## Goal
Find real defects before release. For every finding you must show a concrete failure scenario (inputs/state -> wrong outcome/crash), not a style opinion. Prioritize: data loss, crashes, behavior regressions vs the section-7 checklist, lock/protection bypasses, sync/merge corruption, main-thread hangs, file-handle/disk leaks, memory growth with 10,000 items.

## Method (do all)
1. **Checklist pass**: for each of the 12 items in PLAN.md §7, locate the code path and state VERIFIED / REGRESSED / UNVERIFIABLE with evidence.
2. **Lock bypass hunt**: enumerate every code path that removes items or files (`delete`, `clear`, eviction, folder delete, sync tombstones/merge, migration, corrupt-file handling, edit-mode save, Save All) and prove locked items survive or cite the hole.
3. **Persistence**: kill -9 during save (simulate with a harness writing a 10,000-item store under a loop), v1 -> v2 migration on the user's real `history.json` shape (copy `~/Library/Application Support/Buffer/history.json` into a temp `KLIP_DATA_DIR` - read only, never write to the original), corrupt JSON, missing attachments, non-ASCII filenames, very large clips (>50 KB text, 4096 px image, 600 MB file reference).
4. **Performance**: harness with 10,000 items (mixed kinds, 200 tags, 30 folders): launch load time, `applyFilters` per keystroke, memory after scrolling (thumbnail cache), per-row timers. Report numbers.
5. **Concurrency**: with `-default-isolation MainActor`, look for `DispatchQueue.main.sync` deadlocks, background-queue AppKit drawing, races between debounced save and quit, sync pull vs local edits.
6. **UI logic** via the 2A behavior harness (`scratchpad/harness/`): selection/scope/chip/search combinations, Esc chain, prompts, folder delete branches, drag payload, key monitor dispatch with rebinding.
7. **Sync** (if Phase 4 merged): two stores + fake cloud root: concurrent adds, delete vs edit race, evicted item resurrection, tombstone pruning, corrupt remote file, huge attachment, disable/enable cycles.
8. **Security/privacy**: concealed pasteboard types honored; no network other than the updater; the updater's install script path/quoting with spaces; `KLIP_DATA_DIR` tilde/relative path handling; bookmark resolution of reference files outside the home dir.

## Output
Write `docs/plan/review-5A.md`: a table of findings (id, severity Critical/High/Medium/Low, file:line, scenario, suggested fix, confidence), then the checklist verdicts, then the performance numbers, then "not verifiable without a live session" items. No fixes - task 5C applies them.
Return: the findings table (Critical/High first) and the path of the report.
