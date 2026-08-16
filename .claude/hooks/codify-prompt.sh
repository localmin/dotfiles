#!/usr/bin/env bash
# PostToolUse hook (Claude Code), matcher: Bash.
# Codify nudge at the push checkpoint: after a successful `git push`, suggest
# running the retrospective-codify skill over the work just shipped. PostToolUse
# fires only on success, so reaching here means the push went through. Emits a
# non-blocking additionalContext hint (never blocks); other commands are ignored.
set -uo pipefail

# is_git_push lives in the shared lib (also used by pre-push-review-gate.sh).
source "$(dirname "${BASH_SOURCE[0]}")/lib/git-cmd.sh"

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[[ "$tool" == "Bash" ]] || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
is_git_push "$cmd" || exit 0

ctx="A git push just completed — a natural checkpoint to capture lessons. If this session involved trial-and-error, wrong turns, user corrections, or a non-obvious fix (not a trivial first-try task), run the retrospective-codify skill: pair what failed first with what finally worked, then propose codifying the should-have-known-it insight as one of — an ast-grep rule (statically-detectable code pattern), a hookify rule (a recurring unwanted behavior to block/guard via a hook), a CLAUDE.md rule (short always-on guidance), or a skill (multi-step procedure) — and write only what is approved. If the work was trivial, skip — zero proposals is fine."

jq -nc --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$c}}'
exit 0
