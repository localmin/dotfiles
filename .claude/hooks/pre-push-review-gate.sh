#!/usr/bin/env bash
# PreToolUse hook (Claude Code), matcher: Bash.
# Pre-push review gate: block `git push` until /code-review and
# /security-review have been run for the exact commit being pushed.
# Approval is recorded as the pushed HEAD sha in .git/review-ok; the gate
# re-arms automatically whenever HEAD changes (new commits => re-review).
# The security-guidance plugin still runs as an independent first pass.
set -uo pipefail

# is_git_push lives in the shared lib (also used by codify-prompt.sh).
source "$(dirname "${BASH_SOURCE[0]}")/lib/git-cmd.sh" 2>/dev/null || true
# Fail safe: if the lib isn't linked (e.g. dotfilesLink.sh not re-run on this
# machine), fall back to a conservative detector so the gate still blocks pushes
# instead of silently allowing them. It over-blocks commands that mention both
# `git` and `push` (rare, and only while misconfigured) — the safe direction.
if ! declare -F is_git_push >/dev/null 2>&1; then
  is_git_push() { [[ "$1" == *git* && "$1" == *push* ]]; }
fi

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

# --- Scope of the pending push -------------------------------------------
# Resolve what this push actually introduces, so the gate can size the review
# to the change instead of demanding the same full pass for every commit.
base=""
if upstream="$(git -C "$root" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
  base="$(git -C "$root" merge-base HEAD "$upstream" 2>/dev/null || true)"
fi
if [[ -z "$base" ]]; then
  # New branch with no upstream yet: compare against the default branch.
  for ref in origin/HEAD origin/main origin/master; do
    if git -C "$root" rev-parse --verify -q "$ref" >/dev/null 2>&1; then
      base="$(git -C "$root" merge-base HEAD "$ref" 2>/dev/null || true)"
      [[ -n "$base" ]] && break
    fi
  done
fi

changed=""
[[ -n "$base" ]] && changed="$(git -C "$root" diff --name-only "$base..HEAD" 2>/dev/null || true)"

# Docs-only pushes skip the gate: prose cannot break a build or introduce a
# vulnerability. Anything else -- source, config, workflows, lockfiles -- still
# requires both reviews. Deliberately NOT a size threshold: small diffs are
# routinely where the worst bugs hide.
#
# Match on the extension, never on a directory: a `^docs/` prefix would let
# `docs/install.sh` through. The LICENSE alternative is anchored at both ends
# so `LICENSE.sh` does not pass as `LICENSE`.
if [[ -n "$changed" ]] && ! printf '%s\n' "$changed" | grep -qvE '\.md$|^LICENSE(\.md|\.txt)?$'; then
  echo "Pre-push review gate: docs-only change, skipping /code-review and /security-review." >&2
  exit 0
fi

if [[ -n "$head" && -f "$marker" && "$(cat "$marker" 2>/dev/null)" == "$head" ]]; then
  exit 0   # reviews approved for this exact HEAD -> allow push
fi

# Size only picks the effort level, never whether to review at all. Lockfiles
# are excluded from the count: a dependency bump is thousands of generated
# lines that no reviewer reads, and it would push every bump into a full pass.
review_cmd="/code-review"
if [[ -n "$base" ]]; then
  churn="$(git -C "$root" diff --numstat "$base..HEAD" -- . ':(exclude)*lock.json' ':(exclude)*lock.yaml' ':(exclude)*.lockb' 2>/dev/null \
    | awk '{ added += $1; removed += $2 } END { print added + removed + 0 }')"
  if [[ -n "$churn" && "$churn" -lt 100 ]]; then
    review_cmd="/code-review low"
  fi
fi


cat >&2 <<EOF
Pre-push review gate: this push is blocked until the pending changes are reviewed.

1. Run $review_cmd on the diff and address findings.
2. Run /security-review on the diff and address findings.
3. Record approval for the current commit, then push again:
     git rev-parse HEAD > "$marker"

The gate re-arms automatically when HEAD changes (new commits require a fresh review).
The security-guidance plugin also runs its own pass on commit/push.
EOF
exit 2
