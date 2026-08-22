# Klip v3.0.0

A major update with organized folders, lock protection, Clipfield-inspired UI, rich-text support, file clips, custom shortcuts, and iCloud Drive sync.

## What's New

- **Folders** - Organize your clipboard into custom folders; drag clips to organize
- **Lock & Protect** - Lock important clips to prevent accidental deletion
- **New UI** - Redesigned with Clipfield's clean, modern material design
- **Rich-text Paste** - Capture and paste with formatting; explicit "Paste as Plain Text" option
- **File Clips** - Capture files with previews, save to disk, sync across devices
- **Custom Shortcuts** - Rebind every action in Settings
- **iCloud Sync** (optional) - Sync clipboard across your Macs
- **Better Search** - Filter by type, search OCR text, tags, source apps, file names
- **Accessibility-first** - Request permission on launch instead of blind prompt

## Installation

1. Download the `.dmg` for your Mac (Apple Silicon or Intel)
2. Drag **Klip.app** to Applications
3. Launch Klip and grant Accessibility permission
4. **Important**: Right-click Klip.app and select "Open" the first time (not notarized, signed locally)

Your clipboard history migrates automatically from Buffer; Buffer's data is left untouched.

## Gatekeeper Note

The build is signed with a local identity and is not notarized. On first launch, you may see a Gatekeeper warning. To proceed:

1. Right-click Klip.app in Finder
2. Select "Open" from the context menu
3. Click "Open" in the dialog

This applies only to the first launch.

## Accessibility Permission

Klip requires Accessibility permission to:
- Register the global hotkey (⇧⌘V)
- Auto-paste into the previous application

Grant this permission when prompted on first launch, or via System Settings > Privacy & Security > Accessibility.

## Full Changelog

See [CHANGELOG.md](../../CHANGELOG.md) for the complete list of changes and new features.
