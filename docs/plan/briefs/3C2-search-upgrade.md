# Task 3C part 2 - Search upgrade (Sonnet 5)

WORKTREE: (set at launch, after wave 1 merged). Do NOT commit. Do NOT touch the main checkout.

Read first: `docs/analysis/buffer.md` §3 "Search" (today: non-empty query matches only `.text` items' `textContent`; `#` prefix = tag mode; 200 ms debounce; 90 s persistence), `Views/History/FilterState.swift` (pure `apply`, `Scope`, `ChipFilter`, `matches(_:chip:)`), `Views/History/HistoryViewModel.swift` (search state, `applyFilters`), `Views/History/SearchBar.swift`, `Tests/FilterStateTests.swift`, `Models/ClipboardItem.swift` (`ocrText`, `tags`, `sourceApp`, `fileAttachment`, `kind`), `Services/ClipboardStore.swift` (`fullText(for:)` - do NOT read files during filtering).

## Deliverables (additive only - every query that matched before must still match)
1. `FilterState.apply`: a non-empty query now matches items where any of these contains it case-insensitively (diacritic-insensitive via `.diacriticInsensitive`): `textContent` (all types, incl. the 500-char preview of large text), `ocrText` (so images with recognized text are found), tag names, `sourceApp`, `fileAttachment.originalName` + `additionalNames`, link/email/phone kinds' text. Multi-word queries: all words must match (AND, any field). `#tag` mode unchanged. Images with no OCR text are excluded from text queries as before.
2. Ranking: keep chronological order (pinned first) - no relevance sorting (the user's muscle memory depends on it). Optional: items whose `textContent` starts with the query are not reordered either; do nothing clever.
3. Performance: pre-lowercase per item once per filter pass; the 10,000-item case must stay under ~30 ms on this machine - add a timing test that builds 10,000 synthetic items and asserts `apply` under 150 ms (generous, CI-safe).
4. `SearchBar` placeholder: "Search text, tags, apps, files, OCR…" (one literal). Help text in the empty state when a query matches nothing: "No clips match "…". Try a tag with #, or a chip filter."
5. Tests: extend `Tests/FilterStateTests.swift` (or a new `SearchTests.swift` registered in `TestRunner.swift`): OCR match, tag-name match without `#`, source app match, file name match, multi-word AND, diacritics, old behaviors unchanged, timing.

## Verify
`scripts/gate.sh` green. Remove `build/`.

Owns: `Views/History/FilterState.swift`, `Views/History/SearchBar.swift` (placeholder), `Views/History/ClipList.swift` (empty-state text only), `Tests/FilterStateTests.swift` / `Tests/SearchTests.swift`, `Tests/TestRunner.swift` (suite list).
Return: summary, test output, timing number, `git status --short`.
