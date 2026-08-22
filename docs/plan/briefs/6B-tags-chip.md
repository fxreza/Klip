# Task 6B - Tags chip + "#" legend hint (Sonnet 5)

WORKTREE: (set at launch). Do NOT commit. Do NOT touch the main checkout or `~/Library/Application Support/Klip` (the user's live Klip runs from /Applications - never kill it; test with `scripts/run_app.sh`, which uses `build.noindex/`).

Read: `Views/History/FilterChipBar.swift`, `Views/History/FilterState.swift` (`ChipFilter`, `apply`, `matches`), `Views/History/HistoryViewModel.swift` (`activeTagFilter`, tag-mode search `#`, `TagAutocompleteBar` wiring), `Views/History/TagAutocompleteBar.swift`, `Views/History/ActionBar.swift` (legend tiers), `Views/History/SearchBar.swift`, `Tests/FilterStateTests.swift`, `CHANGELOG.md`, `Info.plist`.

## Deliverables
1. **Tags chip**: add a `Tags` chip (SF `tag`) at the end of the chip row (after Phone). Semantics: active => list shows only clips that have at least one tag (combined with scope/search as usual) AND the tag bar (`TagAutocompleteBar`, all tags sorted by use count then name) is shown under the chips so the user can click a tag to set `activeTagFilter`. Clicking a tag keeps the chip active; clearing the tag filter (⌫ on empty search, the pill's ×) returns to "all tagged clips" while the chip stays active; clicking the chip again or `All` clears both the chip and the tag filter. Typing `#…` in search still works exactly as before and lights the Tags chip while a tag filter is active (keep them consistent: `activeTagFilter != nil` implies the chip reads as active).
2. **Legend**: add `# tags` to the base tier (text: "# tags", help/tooltip "Type #tag in search or use the Tags chip"), placed after `⌥↩ paste plain`. Make sure the full tier still fits at the default 880 pt width (measure with the offscreen harness or a `screencapture` of the test instance; drop it to the reduced tier otherwise and say so).
3. Tests: `FilterStateTests` - `.tagged` chip rule (only tagged items; combined with scope; combined with `#tag`); view-model test that activating the chip shows the bar and deactivating clears the tag filter.
4. `Info.plist` 3.0.2 / build 10; CHANGELOG `## 3.0.2` entry.

## Verify
`scripts/gate.sh` green. `scripts/run_app.sh` + `notifyutil -p com.fxreza.klip.debug.show` + `screencapture -x` showing the Tags chip, the tag bar when active, and the legend with `# tags`. Kill the instance, remove `build.noindex/`.

Owns: `Views/History/FilterChipBar.swift`, `Views/History/FilterState.swift`, `Views/History/HistoryViewModel.swift` (tag/chip logic), `Views/History/TagAutocompleteBar.swift`, `Views/History/ActionBar.swift`, `Views/History/HistoryContentView.swift` (bar placement only), `Tests/**`, `Info.plist`, `CHANGELOG.md`.
Return: summary, screenshot description, gate output, `git status --short`.
