# Task 3H - Font-size sweep outside the history window (Haiku 4.5)

WORKTREE: (set at launch, after wave 1 merged). Do NOT commit. Do NOT touch the main checkout. Do NOT edit `Views/History/**` (already clean) or any `Services/**`.

Read first: `Views/Theme/FontScale.swift` (`KlipFontRole`, `Font.klip(_:)`, `CGFloat.klipScaled(_:preview:)`), `Views/Theme/Theme.swift` (`Theme.icon(_:weight:preview:)`), then grep: `grep -rn "\.font(.system(size\|NSFont.systemFont(ofSize\|\.font(\.system(size" Views/SettingsView.swift Views/Settings Views/Permissions Views/StatusBarController.swift Views/TagChip.swift Views/PasteButton.swift`.

## Rules
- Settings, Permissions and Onboarding windows are **system-styled windows**; they should NOT scale with the history-list font setting. For those, replace `.font(.system(size: N))` with the nearest semantic SwiftUI font (`.body`, `.callout`, `.caption`, `.footnote`, `.headline`, `.title2`, `.largeTitle`) keeping the weight/design modifiers (e.g. `.font(.system(size: 13, weight: .medium))` -> `.font(.callout.weight(.medium))`; monospaced -> `.monospaced()`). Keep the visual size within 1 pt of the original: 10-11 -> `.caption`/`.caption2`, 12 -> `.footnote`, 13 -> `.callout`, 14-15 -> `.body`/`.subheadline`, 17+ -> `.title3`/`.title2`, 20+ -> `.title`, 24+ -> `.largeTitle`.
- Anything that is part of the history window or its toasts/prompts (`Views/TagChip.swift`, `Views/PasteButton.swift`, `Views/History/Toast.swift`) must use `Font.klip(...)`/`Theme.icon` (list roles). If those two files already do, leave them.
- `UpdateService` HUD text (`Services/`) is out of scope.
- Do not change layout numbers (padding/frames) except where a font literal is used to size an icon frame - then use `Theme.icon` or leave the frame as is.

## Deliverables
- Zero `.font(.system(size:` / `NSFont.systemFont(ofSize:` left in the files above (report the before/after counts).
- `scripts/gate.sh` green, warning count unchanged.
- Offscreen render of the Settings window (any tab) and the Permissions view before/after using the harness in `<scratch>/harness/` (adapt its paths; if adapting is not straightforward, skip and say so - the change is mechanical).

Owns: `Views/SettingsView.swift`, `Views/Settings/**`, `Views/Permissions/**`, `Views/StatusBarController.swift`, `Views/TagChip.swift`, `Views/PasteButton.swift`.
Return: before/after counts per file, gate output, `git status --short`.
