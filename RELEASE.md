# Klip Release Workflow Guide

This guide outlines the release process for Klip. A release creates tagged builds in `releases/<version>/` and `dist/` directories, publishes to GitHub, and updates the app's auto-updater.

---

## Prerequisites

- You are on the `main` branch
- The version bump (`Info.plist`) and the `CHANGELOG.md` section are **already committed** - `scripts/release.sh` refuses to run while any tracked file is modified. Untracked files are fine, so the release notes below can be written first and swept into the release commit.
- (Optional) `.env` file with Apple notarization credentials for signed/notarized builds; without it, builds are signed with the local "QTranslate Dev" identity

---

## Step 1: Prepare Release Notes

Create release notes at `releases/v<VERSION>/release_notes.md`:

```bash
mkdir -p releases/v3.3.0
# Edit releases/v3.3.0/release_notes.md with user-facing summary
```

Copy the previous release's file for the shape: the changelog's `### Added` /
`### Changed` / `### Fixed` sections for this version, then the `### Installing`
paragraph about right-click > Open (unnotarized builds trip Gatekeeper on first
launch).

`scripts/release.sh` writes a one-line stub if this file is missing, so a
release published without Step 1 has empty notes.

---

## Step 2: Build Release Artifacts

Use the automated build script:

```bash
sh scripts/release.sh
```

This script:
- Refuses to run with a dirty tracked working tree
- Runs `scripts/gate.sh` (build + QuickLook UI symbol check + full test suite) and stops on any failure
- Builds a universal (arm64 + x86_64) `Klip.app` signed with the local "QTranslate Dev" identity
- Packages `Klip_Universal.zip` into `releases/v<VERSION>/`, and unpacks the app to `dist/app.noindex/Klip.app`
- Generates `checksums.txt`
- Commits `releases/v<VERSION>/` and `dist/` as `release: v<VERSION> artifacts in …`
- Tags `klip-v<VERSION>` (with `-f`), then prints the push command - it does **not** push

Flags: `--notarize` builds through `build_dmg.sh` instead (needs `.env`, and
produces the four `Klip_Silicon`/`Klip_Intel` `.dmg` + `.zip` artifacts rather
than `Klip_Universal.zip`); `--no-tag` skips the tag.

Verify output files in `releases/v3.3.0/`:
- `Klip_Universal.zip` (or the four `Klip_Silicon`/`Klip_Intel` files with `--notarize`)
- `checksums.txt`
- `release_notes.md`

---

## Step 3: Push

`scripts/release.sh` has already committed and tagged. Push both:

```bash
git push origin refs/heads/main:refs/heads/main refs/tags/klip-v3.3.0
```

The explicit refspecs matter: this repo has a branch **and** a tag called
`main`, so a bare `git push origin main` is ambiguous.

---

## Step 4: Publish to GitHub

Create a GitHub release with the built artifacts:

```bash
gh release create klip-v3.3.0 \
  releases/v3.3.0/Klip_Universal.zip \
  releases/v3.3.0/checksums.txt \
  --repo fxreza/Klip \
  --title "Klip v3.3.0" \
  --notes-file releases/v3.3.0/release_notes.md
```

**`--repo fxreza/Klip` is required.** This checkout has an `upstream` remote
pointing at `samirpatil2000/Buffer`, and `gh` resolves that as the default
repo - without the flag the release is aimed at upstream, not at this fork.
Check with `gh repo view --json nameWithOwner`.

The auto-updater reads
`https://api.github.com/repos/fxreza/Klip/releases/latest`, so confirm the new
release is the latest and is neither a draft nor a pre-release:

```bash
gh release view klip-v3.3.0 --repo fxreza/Klip --json tagName,isDraft,isPrerelease,assets
```

---

## Version Configuration

Before building, version numbers must match in three places:

1. **Info.plist**:
   - `CFBundleShortVersionString` = `3.3.0`
   - `CFBundleVersion` = `15` (incremented per build/rebuild)

2. **CHANGELOG.md**:
   - Add new section `## 3.3.0 (2026-08-25)`
   - `Tests/ChangelogServiceTests.swift` fails the gate if the shipping version has no section, because the in-app What's New window would open empty

3. **releases/v3.3.0/release_notes.md**:
   - User-facing summary

---

## Keeping the Xcode Project in Sync

The canonical build (`scripts/build_local.sh` / `scripts/release.sh`) globs its Swift sources, so it never goes stale. `Klip.xcodeproj` does not - it's a convenience for anyone who opens the project in Xcode.

After adding, removing, or moving any `.swift` file under `Models/`, `Services/`, or `Views/`:

```bash
python3 scripts/sync_xcodeproj.py
```

This adds/removes file references in the project file and is idempotent.

CI-style check (fails without writing if out of sync):

```bash
python3 scripts/sync_xcodeproj.py --check
```

---

## Release Structure

Releases are organized by version:

```
releases/
  v2.5.0-upstream/       <- baseline (unmodified upstream)
  v3.0.0/                <- first release of this fork
    Klip_Universal.zip
    checksums.txt
    release_notes.md
  v3.1.0/
    ...
```

Every release so far is the universal-zip shape above. A `--notarize` build
would put `Klip_Silicon.dmg` / `.zip` and `Klip_Intel.dmg` / `.zip` there
instead.

Each folder is permanent - never overwrite a published release.

The `dist/` directory holds the latest live build for quick reference. The
unpacked app lives at `dist/app.noindex/Klip.app` - the `.noindex` suffix keeps
it out of the Spotlight index so it does not show up as a duplicate of
`/Applications/Klip.app` in Spotlight and Raycast. See `AGENTS.md`.

---

## Tag Format

Klip uses the tag format `klip-vX.Y.Z` (e.g., `klip-v3.3.0`). This matches the GitHub release URL and the auto-updater expectations.

The upstream Buffer used `buffer-vX.Y.Z`; Klip's tags are distinct to avoid conflicts.

---

## Auto-Updater

The `UpdateService` checks for new releases at:

```
https://github.com/fxreza/Klip/releases
```

When a new release is published, users see an update prompt. The service:
- Fetches the latest release
- Verifies the code signature
- Downloads and installs the new build
- Shows a native "What's New" HUD with a link to release notes

To disable or point to a different fork, edit `Services/UpdateService.swift`.
