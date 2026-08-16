#!/usr/bin/env bash
# PreToolUse hook (Claude Code), matcher: Bash.
# Pre-push review gate: block `git push` until /code-review and
# /security-review have been run for the exact commit being pushed.
# Approval is recorded as the pushed HEAD sha in .git/review-ok; the gate
# re-arms automatically whenever HEAD changes (new commits => re-review).
# The security-guidance plugin still runs as an independent first pass.
set -uo pipefail

# is_git_push lives in the shared lib (also used by codify-prompt.sh).
source "$(dirname "${BASH_SOURCE[0]}")/lib/git-cmd.sh"

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[[ "$tool" == "Bash" ]] || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
is_git_push "$cmd" || exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$root" ]] || exit 0   # not a git repo: nothing to gate
gitdir="$(git -C "$root" rev-parse --git-dir 2>/dev/null || true)"
[[ -n "$gitdir" ]] || exit 0
[[ "$gitdir" = /* ]] || gitdir="$root/$gitdir"
head="$(git -C "$root" rev-parse HEAD 2>/dev/null || true)"
marker="$gitdir/review-ok"

# Global ast-grep gate (rules codified via retrospective-codify).
# error-severity findings block the push (scan exits non-zero);
# warnings are printed for awareness but do not block.
AST_GREP_GLOBAL_CONFIG="$HOME/dotfiles/coding-agents/ast-grep/sgconfig.yml"
if command -v ast-grep >/dev/null 2>&1 && [[ -f "$AST_GREP_GLOBAL_CONFIG" ]]; then
  scan_out="$(ast-grep scan -c "$AST_GREP_GLOBAL_CONFIG" "$root" 2>&1)"
  scan_rc=$?
  if [[ -n "$scan_out" ]]; then
    printf '%s\n' "$scan_out" >&2
  fi
  if [[ $scan_rc -ne 0 ]]; then
    cat >&2 <<EOF

Pre-push ast-grep gate: error-severity findings above must be fixed before pushing.
Rules live in ~/dotfiles/coding-agents/ast-grep/rules/ (global, fed by retrospective-codify).
EOF
    exit 2
  fi
fi

if [[ -n "$head" && -f "$marker" && "$(cat "$marker" 2>/dev/null)" == "$head" ]]; then
  exit 0   # reviews approved for this exact HEAD -> allow push
fi

cat >&2 <<EOF
Pre-push review gate: this push is blocked until the pending changes are reviewed.

1. Run /code-review on the diff and address findings.
2. Run /security-review on the diff and address findings.
3. Record approval for the current commit, then push again:
     git rev-parse HEAD > "$marker"

The gate re-arms automatically when HEAD changes (new commits require a fresh review).
The security-guidance plugin also runs its own pass on commit/push.
EOF
exit 2
