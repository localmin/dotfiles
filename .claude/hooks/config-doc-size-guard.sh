#!/usr/bin/env bash
# PostToolUse hook (Claude Code), matcher: Edit|Write.
# Non-blocking size guard for config docs: warn when a CLAUDE.md exceeds 200
# lines or a first-party SKILL.md exceeds 500 lines, so they stay skimmable.
# Vendored skills (a `.upstream` file sits beside their SKILL.md) are exempt —
# their length is upstream's call, not ours. Never blocks; emits additionalContext.
set -uo pipefail

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
case "$tool" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac

fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[[ -n "$fp" && -f "$fp" ]] || exit 0

base="$(basename "$fp")"
case "$base" in
  CLAUDE.md) limit=200 ;;
  SKILL.md)
    # exempt vendored skills (payload carries a sibling .upstream marker)
    [[ -f "$(dirname "$fp")/.upstream" ]] && exit 0
    limit=500 ;;
  *) exit 0 ;;
esac

lines="$(wc -l < "$fp" | tr -d ' ')"
[[ "$lines" -gt "$limit" ]] || exit 0

ctx="${base} at ${fp} is ${lines} lines (soft limit ${limit}). Consider splitting: move procedural detail into a referenced skill/section, or extract a sub-doc. This is a non-blocking nudge."
jq -nc --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$c}}'
exit 0
