#!/usr/bin/env bash
# SessionStart hook (Claude Code).
# Surface resume context so interrupted multi-step work can be picked back up
# without re-deriving state: the project's .claude/plans/WIP.md plus any
# uncommitted changes. Stdout from a SessionStart hook is injected as context.
# Stays silent when there is nothing to resume (clean tree, no WIP.md).
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
wip="$root/.claude/plans/WIP.md"
out=""

if [[ -f "$wip" ]]; then
  out+=$'## Resume state — .claude/plans/WIP.md\n\n'
  out+="$(cat "$wip")"
  out+=$'\n\n'
fi

if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  changes="$(git -C "$root" status --short 2>/dev/null | head -40)"
  if [[ -n "$changes" ]]; then
    out+=$'## Uncommitted changes (git status --short)\n\n```\n'
    out+="$changes"
    out+=$'\n```\n'
  fi
fi

if [[ -n "$out" ]]; then
  printf '%s\n' "$out"
fi
