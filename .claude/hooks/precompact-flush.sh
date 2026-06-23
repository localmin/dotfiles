#!/usr/bin/env bash
# PreCompact hook (Claude Code).
# Best-effort reminder fired right before context is summarized: flush the
# current in-flight state into .claude/plans/WIP.md (current task, done /
# in-progress / next step, uncommitted files, recent decisions) so the work
# survives compaction. Only nudges when there is uncommitted work to lose.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ -n "$(git -C "$root" status --short 2>/dev/null)" ]]; then
    printf '%s\n' "Before compaction: flush current progress into $root/.claude/plans/WIP.md (current task, done / in-progress / next step, uncommitted files, recent decisions) so interrupted work stays resumable."
  fi
fi
