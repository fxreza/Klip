#!/bin/bash
# Merge gate: build + tests must both succeed. Exits non-zero otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build_local.sh > build-gate.log 2>&1 || { grep -E "error:" build-gate.log | head -20; echo "BUILD FAILED"; exit 1; }
grep -E "Compiler warnings|Authority" build-gate.log || true
scripts/run_tests.sh > tests-gate.log 2>&1 || { tail -30 tests-gate.log; echo "TESTS FAILED"; exit 1; }
tail -1 tests-gate.log
rm -rf build.noindex build-gate.log tests-gate.log
echo "GATE OK"
