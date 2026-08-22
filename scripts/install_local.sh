#!/bin/bash
# Install dist/app.noindex/Klip.app into /Applications, replacing upstream Buffer (approved by the user on 2026-08-22):
#  1. back up ~/Library/Application Support/Buffer to releases/backup-<date>/ (copy, original untouched)
#  2. quit a running /Applications/Buffer.app (graceful, then SIGTERM)
#  3. move /Applications/Buffer.app to the Trash (recoverable)
#  4. copy dist/app.noindex/Klip.app to /Applications/Klip.app (replacing a previous Klip.app after moving it to the Trash)
#  5. launch Klip
# Usage: scripts/install_local.sh [--no-launch] [--keep-buffer]
set -euo pipefail
cd "$(dirname "$0")/.."
LAUNCH=1; KEEP=0
for a in "$@"; do case "$a" in --no-launch) LAUNCH=0;; --keep-buffer) KEEP=1;; *) echo "unknown arg $a"; exit 2;; esac; done
[[ -d dist/app.noindex/Klip.app ]] || { echo "dist/app.noindex/Klip.app missing - run scripts/release.sh first"; exit 1; }

STAMP=$(date +%Y%m%d-%H%M%S)
SRC="$HOME/Library/Application Support/Buffer"
if [[ -d "$SRC" ]]; then
  DST="releases/backup-$STAMP/Buffer-AppSupport"
  mkdir -p "$DST"; ditto "$SRC" "$DST"
  defaults export com.samirpatil.Buffer "releases/backup-$STAMP/com.samirpatil.Buffer.plist" 2>/dev/null || true
  echo "Backed up Buffer data to releases/backup-$STAMP ($(du -sh "$DST" | cut -f1))"
fi

trash() { # move to Trash via Finder (recoverable); fall back to mv into ~/.Trash
  local p="$1"; [[ -e "$p" ]] || return 0
  osascript -e "tell application \"Finder\" to delete POSIX file \"$p\"" >/dev/null 2>&1 || mv "$p" "$HOME/.Trash/$(basename "$p")-$STAMP"
  echo "Moved $p to Trash"
}

if pgrep -f "/Applications/Buffer.app/Contents/MacOS/Buffer" >/dev/null; then
  osascript -e 'tell application "Buffer" to quit' >/dev/null 2>&1 || true; sleep 2
  pkill -f "/Applications/Buffer.app/Contents/MacOS/Buffer" 2>/dev/null || true; sleep 1
  echo "Quit upstream Buffer"
fi
[[ $KEEP -eq 1 ]] || trash "/Applications/Buffer.app"

if pgrep -f "/Applications/Klip.app/Contents/MacOS/Klip" >/dev/null; then
  osascript -e 'tell application "Klip" to quit' >/dev/null 2>&1 || true; sleep 2
  pkill -f "/Applications/Klip.app/Contents/MacOS/Klip" 2>/dev/null || true; sleep 1
fi
trash "/Applications/Klip.app"
ditto dist/app.noindex/Klip.app /Applications/Klip.app
xattr -cr /Applications/Klip.app 2>/dev/null || true
codesign -dvv /Applications/Klip.app 2>&1 | grep -E "^Authority|^Identifier" | head -2
if [[ $LAUNCH -eq 1 ]]; then open -a /Applications/Klip.app; sleep 3; pgrep -fl "/Applications/Klip.app/Contents/MacOS/Klip" | head -1 || echo "Klip did not stay running - check Console"; fi
echo "Installed /Applications/Klip.app"
