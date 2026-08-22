# Task 5D - Docs, attribution, changelog, release notes, version bump (Haiku 4.5)

WORKTREE: (set at launch). Do NOT commit. Do NOT touch the main checkout. Do NOT edit any `.swift`, script or pbxproj file except `Info.plist`.

Read first: `docs/plan/PLAN.md` (sections 0, 2 decisions log, 6 traceability), `docs/plan/PROGRESS.md`, `README.md` (upstream Buffer's), `RELEASE.md`, `SECURITY.md`, `releases/README.md`, `dist/README.md`, `LICENSE`, `reference/clipfield/LICENSE`, `reference/pesty/LICENSE`.

## Deliverables
1. `README.md` - rewrite for **Klip** (keep it factual, no marketing fluff): one-paragraph intro ("Klip is a fork of Buffer by @samirpatil2000 with a Clipfield-inspired UI, folders, locks, file clips, custom shortcuts and iCloud Drive sync"), a Features list derived from PLAN.md §6 (only features that PROGRESS.md marks merged), Requirements (macOS 13+, Accessibility for auto-paste), Install (from `releases/` / GitHub releases at https://github.com/fxreza/Klip/releases; Gatekeeper note: the build is signed with a local identity and not notarized - right-click > Open the first time), Build from source (`scripts/build_local.sh`, `scripts/run_tests.sh`, `scripts/gate.sh`, `build_dmg.sh` with `.env` for notarization), Data location (`~/Library/Application Support/Klip`, migrated from Buffer on first launch, Buffer's data left untouched), Sync (iCloud Drive, how it works, limitations), Credits (Buffer, Clipfield, Pesty with links and MIT), License. Keep upstream's badges out; remove upstream download links; keep the Star History section out.
2. `ATTRIBUTION.md` - MIT notices: Buffer (Copyright holder from upstream `LICENSE`), Clipfield (Copyright 2026 Alex Jolley) for the ported files (list them: `Views/Theme/*`, `Views/History/PanelResizer.swift`, `Views/Settings/HotkeyRecorder.swift`, `Services/PermissionsState.swift`, `Views/Permissions/OnboardingView.swift`, `Services/PasteboardFlavors.swift`, `Services/ContentDetector.swift` heuristics), Pesty (copyright from its LICENSE) for the iCloud Drive sync approach.
3. `CHANGELOG.md` - `## 3.0.0 (2026-08-22)` grouped Added / Changed / Fixed / Internal, from PROGRESS.md and the git log (`git log baseline-v2.5.0..HEAD --oneline`). Under Changed, state the two approved behavior changes explicitly: default paste keeps formatting (with the "Always paste as plain text" setting), and the app/bundle rename with automatic migration.
4. `releases/v3.0.0/release_notes.md` - user-facing notes (short), plus the Gatekeeper note and "grant Accessibility once".
5. `SECURITY.md` - update the local-only storage claim: storage stays local unless iCloud Drive sync is enabled by the user; what is synced; no telemetry; updater contacts GitHub only.
6. `RELEASE.md` - update for this fork: tags are `klip-vX.Y.Z`, artifacts go to `releases/<version>/` and `dist/`, `scripts/release.sh` usage, `scripts/sync_xcodeproj.py` note (5B adds its own section - keep it).
7. `Info.plist`: `CFBundleShortVersionString` 3.0.0, `CFBundleVersion` 8.
8. `docs/README.md`: add the briefs folder and the review report.

Owns: the files listed above only.
Return: list of files changed, `git status --short`.
