#!/usr/bin/env bash
# Shared helpers for the git-related Claude Code hooks. Sourced by
# pre-push-review-gate.sh and codify-prompt.sh so the parsing lives in one place.

# is_git_push CMD — return 0 only when the command actually invokes the `git push`
# subcommand (not merely mentions "push", e.g. `git commit -m "...push..."` or echo).
# Splits on &&/||/;/| and, per segment, skips leading VAR=val env assignments and
# git global flags before checking that the subcommand is `push`.
is_git_push() {
  local cmd="$1" seg norm
  norm="${cmd//&&/$'\n'}"; norm="${norm//||/$'\n'}"
  norm="${norm//;/$'\n'}"; norm="${norm//|/$'\n'}"
  while IFS= read -r seg; do
    local toks; read -ra toks <<<"$seg"
    local k=0
    while [[ $k -lt ${#toks[@]} && "${toks[$k]:-}" == *=* && "${toks[$k]:-}" != -* ]]; do k=$((k+1)); done
    [[ "${toks[$k]:-}" == git ]] || continue
    local j=$((k+1))
    while [[ $j -lt ${#toks[@]} && "${toks[$j]}" == -* ]]; do
      case "${toks[$j]}" in
        -C|-c|--git-dir|--work-tree|--namespace|--exec-path) j=$((j+2));;
        *) j=$((j+1));;
      esac
    done
    [[ "${toks[$j]:-}" == push ]] && return 0
  done <<<"$norm"
  return 1
}
