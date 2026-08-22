# Klip Release Workflow Guide

This guide outlines the release process for Klip. A release creates tagged builds in `releases/<version>/` and `dist/` directories, publishes to GitHub, and updates the app's auto-updater.

---

## Prerequisites

- Working directory is clean (`git status`)
- You are on the `main` branch
- (Optional) `.env` file with Apple notarization credentials for signed/notarized builds; without it, builds are ad-hoc signed locally

---

## Step 1: Prepare Release Notes

Create release notes at `releases/v<VERSION>/release_notes.md`:

```bash
mkdir -p releases/v3.0.0
# Edit releases/v3.0.0/release_notes.md with user-facing summary
```

---

## Step 2: Build Release Artifacts

Use the automated build script:

```bash
sh scripts/release.sh
```

This script:
- Builds arm64 and x86_64 binaries
- Signs with the local "QTranslate Dev" identity (ad-hoc if no .env)
- Notarizes (if .env present with Apple credentials; otherwise ad-hoc)
- Creates `.dmg` and `.zip` archives
- Generates `checksums.txt`
- Copies artifacts to `releases/v<VERSION>/` and `dist/`

Verify output files in `releases/v3.0.0/`:
- `Klip_Silicon.dmg` & `Klip_Silicon.zip`
- `Klip_Intel.dmg` & `Klip_Intel.zip`
- `checksums.txt`
- `release_notes.md`

---

## Step 3: Commit and Tag

```bash
git add releases/v3.0.0/ dist/ CHANGELOG.md
git commit -m "release: v3.0.0"

# Tag (format: klip-vX.Y.Z)
git tag klip-v3.0.0
git push origin main klip-v3.0.0
```

---

## Step 4: Publish to GitHub (Optional)

Create a GitHub release with the built artifacts:

```bash
gh release create klip-v3.0.0 \
  releases/v3.0.0/Klip_Silicon.dmg \
  releases/v3.0.0/Klip_Silicon.zip \
  releases/v3.0.0/Klip_Intel.dmg \
  releases/v3.0.0/Klip_Intel.zip \
  --title "Klip v3.0.0" \
  --notes-file releases/v3.0.0/release_notes.md
```

The auto-updater will detect this release and offer it to users.

---

## Version Configuration

Before building, version numbers must match in three places:

1. **Info.plist**:
   - `CFBundleShortVersionString` = `3.0.0`
   - `CFBundleVersion` = `8` (incremented per build/rebuild)

2. **CHANGELOG.md**:
   - Add new section `## 3.0.0 (2026-08-22)`

3. **releases/v3.0.0/release_notes.md**:
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
    Klip_Silicon.dmg
    Klip_Silicon.zip
    Klip_Intel.dmg
    Klip_Intel.zip
    release_notes.md
    checksums.txt
  v3.1.0/
    ...
```

Each folder is permanent - never overwrite a published release.

The `dist/` directory holds the latest live build for quick reference. The
unpacked app lives at `dist/app.noindex/Klip.app` - the `.noindex` suffix keeps
it out of the Spotlight index so it does not show up as a duplicate of
`/Applications/Klip.app` in Spotlight and Raycast. See `CLAUDE.md`.

---

## Tag Format

Klip uses the tag format `klip-vX.Y.Z` (e.g., `klip-v3.0.0`). This matches the GitHub release URL and the auto-updater expectations.

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
