#!/bin/bash
# Manager helper: commit a task worktree, merge it into main, gate, push only on success.
# Usage: scripts/merge_task.sh <task-id> "<commit message>" [--no-remove]
# Exits 1 (without pushing) when the merge conflicts or the gate fails; main is then left
# with the merge commit for manual resolution - run scripts/gate.sh after fixing, then push.
set -euo pipefail
cd "$(dirname "$0")/.."
ID="$1"; MSG="$2"; REMOVE=1; [[ "${3:-}" == "--no-remove" ]] && REMOVE=0
WT="/private/tmp/claude-501/-Users-sam-Claude-Code-clipboard-manager/3854505a-128a-45e2-b039-51ef49965b3a/scratchpad/wt/$ID"
[[ -d "$WT" ]] || { echo "no worktree $WT"; exit 2; }

git -C "$WT" add -A
if ! git -C "$WT" diff --cached --quiet; then
  git -C "$WT" commit -q -m "$MSG

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
fi
if ! git merge --no-ff "task/$ID" -m "merge task/$ID: ${MSG%%$'\n'*}" >/tmp/merge.out 2>&1; then
  grep -i conflict /tmp/merge.out || cat /tmp/merge.out
  echo "MERGE CONFLICT - resolve, then: scripts/gate.sh && git add -A && git commit --no-edit && git push origin refs/heads/main:refs/heads/main"
  exit 1
fi
if scripts/gate.sh >/tmp/gate.out 2>&1; then
  tail -2 /tmp/gate.out
else
  grep -E "error:|FAILED" /tmp/gate.out | head -20
  echo "GATE FAILED after merging task/$ID - NOT pushed. Fix on main, re-run scripts/gate.sh, then push."
  exit 1
fi
if python3 scripts/sync_xcodeproj.py --check >/dev/null 2>&1; then :; else
  python3 scripts/sync_xcodeproj.py >/dev/null && plutil -lint Klip.xcodeproj/project.pbxproj >/dev/null && git add Klip.xcodeproj && git commit -q -m "build: re-sync xcodeproj after task/$ID"
fi
git push -q origin refs/heads/main:refs/heads/main
[[ $REMOVE -eq 1 ]] && git worktree remove --force "$WT"
git log --oneline -1
echo "MERGED+PUSHED task/$ID"
