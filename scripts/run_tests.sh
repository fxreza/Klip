#!/bin/bash
# Dependency-free test runner: compiles the app sources (minus the @main
# BufferApp.swift) together with Tests/*.swift into a standalone binary and
# runs it. No XCTest, no Xcode, works offline and without a .env.
#
# Usage: scripts/run_tests.sh [-v]
#   -v  show compiler output even on success (it is always shown on failure)

set -euo pipefail

cd "$(dirname "$0")/.."

VERBOSE=0
if [[ "${1:-}" == "-v" ]]; then
    VERBOSE=1
fi

BUILD_DIR="build/tests"
mkdir -p "$BUILD_DIR"

# Root-level *.swift minus the @main file (it declares its own @main App
# scene, which would collide with Tests/TestRunner.swift's @main).
ROOT_SOURCES=()
for f in *.swift; do
    [[ "$f" == "BufferApp.swift" ]] && continue
    ROOT_SOURCES+=("$f")
done

# Models/Services/Views recursively, so future subfolders are picked up
# automatically, same as build_dmg.sh's glob.
APP_SOURCES=()
while IFS= read -r -d '' f; do
    APP_SOURCES+=("$f")
done < <(find Models Services Views -name '*.swift' -print0)

TEST_SOURCES=(Tests/*.swift)

SOURCES=("${ROOT_SOURCES[@]}" "${APP_SOURCES[@]}" "${TEST_SOURCES[@]}")

LOG_FILE="$(mktemp)"
trap 'rm -f "$LOG_FILE"' EXIT

set +e
swiftc \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -target arm64-apple-macosx13.0 \
    -parse-as-library \
    -default-isolation MainActor \
    -framework Cocoa \
    -framework SwiftUI \
    -framework Carbon \
    -framework Quartz \
    -framework QuickLookThumbnailing \
    "${SOURCES[@]}" \
    -o "$BUILD_DIR/runner" \
    > "$LOG_FILE" 2>&1
BUILD_STATUS=$?
set -e

if [[ $BUILD_STATUS -ne 0 ]]; then
    echo "== compile failed =="
    cat "$LOG_FILE"
    exit "$BUILD_STATUS"
fi

if [[ $VERBOSE -eq 1 ]]; then
    cat "$LOG_FILE"
fi

"$BUILD_DIR/runner"
