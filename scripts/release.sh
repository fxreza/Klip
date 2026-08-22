#!/bin/bash
# Release: build a universal Klip.app, package zip (+ DMGs when build_dmg.sh can sign/notarize),
# copy artifacts to releases/<version>/ and dist/, write checksums, tag klip-v<version>.
#
# Usage: scripts/release.sh [--no-tag] [--notarize]
#   --notarize  run build_dmg.sh (needs .env with SIGN_IDENTITY/NOTARY_PROFILE) instead of build_local.sh
#   --no-tag    skip the git tag
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARIZE=0; TAG=1
for a in "$@"; do case "$a" in --notarize) NOTARIZE=1;; --no-tag) TAG=0;; *) echo "unknown arg $a"; exit 2;; esac; done

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
OUT="releases/v${VERSION}"
echo "Releasing Klip ${VERSION} (build ${BUILD}) -> ${OUT}"

if [[ -n "$(git status --porcelain | grep -v '^?? ' || true)" ]]; then
  echo "Working tree has uncommitted changes; commit first." >&2; exit 1
fi

scripts/gate.sh

mkdir -p "$OUT" dist/app.noindex
if [[ $NOTARIZE -eq 1 ]]; then
  sh build_dmg.sh
  cp -f Klip_Silicon.dmg Klip_Silicon.zip Klip_Intel.dmg Klip_Intel.zip "$OUT"/
  rm -rf dist/app.noindex/Klip.app; ditto -x -k Klip_Silicon.zip dist/app.noindex/
else
  scripts/build_local.sh --arch both --dist
  rm -f "$OUT/Klip_Universal.zip"
  (cd build.noindex && ditto -c -k --keepParent Klip.app "../$OUT/Klip_Universal.zip")
  lipo -info build.noindex/Klip.app/Contents/MacOS/Klip
fi

(cd "$OUT" && shasum -a 256 *.zip *.dmg 2>/dev/null > checksums.txt || shasum -a 256 *.zip > checksums.txt; cat checksums.txt)
[[ -f "$OUT/release_notes.md" ]] || echo "# Klip v${VERSION}" > "$OUT/release_notes.md"
rm -rf build.noindex

git add "$OUT" dist
git commit -q -m "release: v${VERSION} artifacts in ${OUT} and dist/" || true
if [[ $TAG -eq 1 ]]; then
  git tag -f "klip-v${VERSION}"
  echo "Tagged klip-v${VERSION}. Push with: git push origin refs/heads/main:refs/heads/main refs/tags/klip-v${VERSION}"
fi
echo "Done: $(ls "$OUT")"
