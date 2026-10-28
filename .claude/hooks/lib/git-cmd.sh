#!/usr/bin/env bash
# Shared helpers for the git-related Claude Code hooks. Sourced by
# pre-push-review-gate.sh and codify-prompt.sh so the parsing lives in one place.

# Commands that run another command (and may change its cwd or environment first,
# e.g. `env -C dir`, `builtin cd`). Pushes behind them are detected but never resolved.
_GIT_CMD_WRAPPERS="env command builtin nohup time nice sudo exec xargs"

# git_push_dir CMD BASE — print the directory the `git push` in CMD runs from,
# starting at BASE (the session cwd). Follows `cd`/`pushd DIR` segments that come
# before the push and `git -C DIR` options (relative paths compose, as git does).
# Returns 1 when CMD has no push, 2 when the target cannot be resolved statically
# (subshells, groups, expansions, --git-dir/--work-tree, GIT_DIR/GIT_WORK_TREE,
# cd options, or commands that move/replace the shell) so callers can fail closed.
git_push_dir() {
  local cmd="$1" dir="$2" seg norm
  is_git_push "$cmd" || return 1
  [[ "$cmd" =~ [\(\)\{\}\$\`] ]] && return 2
  [[ "$cmd" == *GIT_DIR=* || "$cmd" == *GIT_WORK_TREE=* ]] && return 2
  norm="${cmd//&&/$'\n'}"; norm="${norm//||/$'\n'}"
  norm="${norm//;/$'\n'}"; norm="${norm//|/$'\n'}"; norm="${norm//&/$'\n'}"
  while IFS= read -r seg; do
    while [[ "$seg" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=(\"[^\"]*\"|\'[^\']*\'|[^[:space:]]*)([[:space:]]+|$) ]]; do
      seg="${seg#"${BASH_REMATCH[0]}"}"
    done
    local toks; read -ra toks <<<"$seg"
    case "${toks[0]:-}" in
      cd|pushd)
        _git_cmd_resolve "$dir" "${toks[1]:-$HOME}" || return 2
        dir="$_git_cmd_resolved"; continue;;
      popd|eval|source|.|export) return 2;;
      git) ;;
      "") continue;;
      *) [[ " $_GIT_CMD_WRAPPERS " == *" ${toks[0]} "* ]] && return 2; continue;;
    esac
    is_git_push "$seg" || continue
    local d="$dir" j=1
    while [[ $j -lt ${#toks[@]} && "${toks[$j]}" == -* ]]; do
      case "${toks[$j]}" in
        -C) _git_cmd_resolve "$d" "${toks[$((j+1))]:-}" || return 2
            d="$_git_cmd_resolved"; j=$((j+2));;
        --git-dir|--git-dir=*|--work-tree|--work-tree=*) return 2;;
        -c|--namespace|--exec-path) j=$((j+2));;
        *) j=$((j+1));;
      esac
    done
    printf '%s\n' "$d"; return 0
  done <<<"$norm"
  return 1
}

# _git_cmd_resolve BASE PATH — set _git_cmd_resolved to PATH resolved against BASE.
# Fails on anything that is not plain static text (quotes, globs, empty) and on
# option-like operands (`cd -`, `cd -P dir`), whose target is not the operand.
_git_cmd_resolve() {
  local base="$1" p="$2"
  [[ -n "$p" && "$p" != -* && "$p" =~ ^[A-Za-z0-9_./~+,@%=:-]+$ ]] || return 1
  case "$p" in
    "~") p="$HOME";;
    "~/"*) p="$HOME/${p#\~/}";;
    "~"*) return 1;;
  esac
  [[ "$p" == /* ]] && _git_cmd_resolved="$p" || _git_cmd_resolved="$base/$p"
}

# is_git_push CMD — return 0 only when the command actually invokes the `git push`
# subcommand (not merely mentions "push", e.g. `git commit -m "...push..."` or echo).
# Splits on &&/||/;/|/& and, per segment, strips leading VAR=val env assignments and
# git global flags before checking that the subcommand is `push`.
#
# A `--dry-run` push contacts the remote but sends nothing, so it is deliberately
# NOT reported as a push: gating it blocks a harmless connectivity check, and the
# post-push codify prompt would fire for a push that never happened.
is_git_push() {
  local cmd="$1" seg norm
  norm="${cmd//&&/$'\n'}"; norm="${norm//||/$'\n'}"
  norm="${norm//;/$'\n'}"; norm="${norm//|/$'\n'}"; norm="${norm//&/$'\n'}"
  # Grouping characters also delimit commands: `(cd x && git push)` would otherwise
  # leave a `push)` token that no longer reads as the push subcommand.
  norm="${norm//[(){\}]/$'\n'}"
  while IFS= read -r seg; do
    local raw="$seg"
    # Peel env assignments off the raw string rather than off tokens: a quoted
    # value can contain spaces (GIT_SSH_COMMAND='ssh -i key'), which word
    # splitting would tear apart, hiding the `git` that follows.
    while [[ "$seg" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=(\"[^\"]*\"|\'[^\']*\'|[^[:space:]]*)([[:space:]]+|$) ]]; do
      seg="${seg#"${BASH_REMATCH[0]}"}"
    done
    local toks; read -ra toks <<<"$seg"
    # A wrapper (env/command/nohup/...) can carry its own options and values before
    # `git`, which this parser cannot follow; any `git ... push` behind one counts as
    # a push, with no dry-run exemption (fail closed).
    if [[ " $_GIT_CMD_WRAPPERS " == *" ${toks[0]:-} "* ]]; then
      local k seen_git=0
      for ((k = 1; k < ${#toks[@]}; k++)); do
        [[ "${toks[$k]}" == git ]] && seen_git=1
        [[ $seen_git -eq 1 && "${toks[$k]}" == push ]] && return 0
      done
      continue
    fi
    [[ "${toks[0]:-}" == git ]] || continue
    local j=1
    while [[ $j -lt ${#toks[@]} && "${toks[$j]}" == -* ]]; do
      case "${toks[$j]}" in
        -C|-c|--git-dir|--work-tree|--namespace|--exec-path) j=$((j+2));;
        *) j=$((j+1));;
      esac
    done
    [[ "${toks[$j]:-}" == push ]] || continue
    # Exempt a dry-run only when every option after `push` is one we fully understand.
    # git's option parser is hard to mirror in shell (it accepts abbreviations such as
    # --push-opt and --no-dry, takes values from the next token, and bundles short
    # flags), so rather than chase each quirk we allowlist the plain flags and treat
    # any other dash-prefixed token as "unknown" -> a push. The gate fails closed.
    local m dry=0 unknown=0 endopts=0 tok
    local plain='^[A-Za-z0-9_./:@+,%=^-]+$' redir='^[0-9]*>>?[A-Za-z0-9_./-]*$'
    for ((m = j + 1; m < ${#toks[@]}; m++)); do
      tok="${toks[$m]}"
      if [[ $endopts -eq 1 ]]; then
        # After `--` nothing is a flag any more, but it still has to be static text.
        [[ "$tok" =~ $plain || "$tok" =~ $redir ]] || unknown=1
        continue
      fi
      case "$tok" in
        --) endopts=1;;             # the rest are refspecs
        --dry-run|-n) dry=1;;
        --no-dry-run) dry=0;;       # exact only; the last of the two wins
        --verbose|--quiet|--force|--set-upstream|--tags|--all|--follow-tags|--no-verify|--atomic|--thin|--no-thin|--progress|--prune|--porcelain|--delete|--force-with-lease|--force-if-includes) ;;
        --force-with-lease=*|--force-if-includes=*|--signed=*|--repo=*|--push-option=*|--receive-pack=*|--exec=*|--recurse-submodules=*)
          # The value is shell text too (`--signed=$(git${IFS}push)`), so it must be static.
          [[ "${tok#*=}" =~ $plain ]] || unknown=1;;
        --?*) unknown=1;;
        -[!-]*)
          # Short bundle: only value-less flags qualify (no `o`, which takes a value).
          if [[ "$tok" =~ ^-[vqfudn]+$ ]]; then
            [[ "$tok" == *n* ]] && dry=1
          else
            unknown=1
          fi;;
        # A remote, a refspec or a redirection. read -ra does not unquote or expand, so
        # `"--no-dry-run"`, `$X` or `$(git push)` would look like harmless words here
        # while the shell turns them into a flag or a second push: only static text
        # counts, anything else is unknown.
        *) [[ "$tok" =~ $plain || "$tok" =~ $redir ]] || unknown=1;;
      esac
    done
    # One invariant for the whole segment, not per region: with no quoting, expansion,
    # grouping or glob characters anywhere (env assignments and git global options
    # included) the shell cannot rewrite what we parsed, so we see what git sees.
    local meta="[][\$\`\\\\\"'(){}*?~<]"
    [[ "$raw" =~ $meta ]] && unknown=1
    [[ $dry -eq 1 && $unknown -eq 0 ]] && continue
    return 0
  done <<<"$norm"
  return 1
}
