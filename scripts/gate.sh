#!/bin/bash
# Merge gate: build + symbol check + tests must all succeed. Exits non-zero otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build_local.sh > build-gate.log 2>&1 || { grep -E "error:" build-gate.log | head -20; echo "BUILD FAILED"; exit 1; }
grep -E "Compiler warnings|Authority" build-gate.log || true

# QuickLook *UI* must never be linked back in (3.0.1). `-[QLPreviewView
# setPreviewItem:]` raises a QuickLook assertion and aborts the process when it
# is called from a SwiftUI layout pass, which is exactly where
# `NSViewRepresentable.updateNSView` runs — that was the 3.0.0 file-preview
# crash. Thumbnails come from QLThumbnailGenerator (QuickLookThumbnailing)
# instead; nothing in the app may reference a QuickLook UI class.
QL_BIN="build.noindex/Klip.app/Contents/MacOS/Klip"
# The path above said `build/` until 3.1.0, which stopped existing when the
# output directory gained its `.noindex` suffix (see AGENTS.md). `nm` failed,
# the grep counted nothing, and this check passed without ever reading the
# binary — a dead gate guarding against the 3.0.0 file-preview crash. Missing
# binary is now a hard failure so it cannot silently pass again.
if [[ ! -f "$QL_BIN" ]]; then
    echo "QUICKLOOK UI SYMBOL CHECK FAILED: no binary at ${QL_BIN}"
    exit 1
fi
QL_HITS=$(nm -u "$QL_BIN" | grep -c "QLPreviewView" || true); QL_HITS=${QL_HITS:-0}
if [[ "$QL_HITS" -ne 0 ]]; then
    nm -u "$QL_BIN" | grep "QLPreviewView"
    echo "QUICKLOOK UI SYMBOL CHECK FAILED: QLPreviewView is linked into the binary"
    exit 1
fi
echo "QuickLook UI symbol check: clean (0 QLPreviewView references)"

scripts/run_tests.sh > tests-gate.log 2>&1 || { tail -30 tests-gate.log; echo "TESTS FAILED"; exit 1; }
tail -1 tests-gate.log
rm -rf build.noindex build-gate.log tests-gate.log
echo "GATE OK"
