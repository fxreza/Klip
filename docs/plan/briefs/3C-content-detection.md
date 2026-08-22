# Task 3C (backend half) - Content kind detection (Sonnet 5)

WORKTREE: (set at launch). Do NOT commit. Do NOT touch the main checkout. Do NOT edit anything under `Views/` - the UI shell is being rebuilt concurrently by task 2A, which consumes `item.kind` for its filter chips.

Read first: `docs/plan/PLAN.md` (Phase 3 row 3C), `docs/analysis/clipfield.md` §3 (SmartTagger / chip types), then `reference/clipfield/Sources/Clipfield/Tagging/SmartTagger.swift` and `Models/SmartTag.swift`, `Models/ClipKind.swift`; ours: `Models/ContentKind.swift`, `Models/ClipboardItem.swift`, `Services/ClipboardWatcher.swift`, `Services/ClipboardStore.swift` (load path, `saveQueue`, debounced save), `Tests/TestRunner.swift`.

## Deliverables
1. `Services/ContentDetector.swift` - `enum ContentDetector` with `static func detect(text: String) -> ContentKind` (pure, fast, no main-actor requirement; mark `nonisolated` where needed given the `-default-isolation MainActor` build flag). Rules, evaluated on the trimmed text, first match wins:
   - `.link`: single line and (`NSDataDetector` link result spans the whole string, or it starts with `http://`, `https://`, `ftp://`, `mailto:` is NOT link, `www.`+dot counts as link).
   - `.email`: whole string matches a standard email regex.
   - `.phone`: `NSDataDetector` phone result spanning the whole string, length 7-20 chars.
   - `.color`: `^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$` or `^(rgb|rgba|hsl|hsla)\(.+\)$` (case-insensitive), max 64 chars.
   - `.code`: port Clipfield's `looksLikeCode` heuristic (multi-line with braces/semicolons/indentation, keywords like `func|def|class|import|return|const|let|var|=>|#include|SELECT ... FROM`, JSON objects). Must not flag ordinary prose; single short lines are never code unless they look like a shell command starting with `$ `, `git `, `npm `, `brew `, `curl `, `ssh `.
   - `.text` otherwise. (`.richText` is assigned elsewhere when an item has RTF/flavors; `.image` for images; `.file` for file attachments.)
   Also `static func detect(for item: ClipboardItem, fullText: String?) -> ContentKind` that maps image/file items and falls back to `textContent` (for file-backed large text use the 500-char preview - good enough).
2. `Services/ClipboardWatcher.swift`: set `kind` on every new item at capture (text via detector, image `.image`). Keep everything else identical.
3. `Services/ClipboardStore.swift`: `func backfillKindsIfNeeded()` - after load, on a utility queue, compute kinds for items with `kind == nil`, then apply on the main actor in one batch and save (debounced). Must not block launch; must be idempotent; call it from `init` after `loadHistory()` (or from AppDelegate if init timing is awkward - one line, say which).
4. Tests `Tests/ContentDetectorTests.swift` (table of at least 30 cases incl. tricky ones: "Call me at 555-0100 tomorrow" is text, "https://x.y/z?q=1" link, "#FFF" color, "#hashtag" text, "rgb(1,2,3)" color, JSON blob code, a Swift snippet code, a markdown paragraph text, "john@doe.com" email, "mailto:john@doe.com" link, URL with trailing period text?) and `Tests/ClipboardStoreTests.swift` additions for backfill (items without kind get kinds after `backfillKindsIfNeeded()` + flush). Register suites in `TestRunner.swift` (suite list only).

## Verify
`scripts/gate.sh` green. Run `scripts/run_app.sh`, `pbcopy` a URL, a hex color and a sentence, `notifyutil -p com.fxreza.klip.debug.quit`, confirm `build/test-data/history.json` has the right `kind` per item. Remove `build/`.

Owns: `Services/ContentDetector.swift`, `Services/ClipboardWatcher.swift`, `Services/ClipboardStore.swift` (backfill only), `Tests/ContentDetectorTests.swift`, `Tests/ClipboardStoreTests.swift` (additions), `Tests/TestRunner.swift` (suite list), optionally one line in `AppDelegate.swift`.
Return: summary, rules as implemented, test output, `git status --short`.
