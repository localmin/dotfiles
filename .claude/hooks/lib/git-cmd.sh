#!/usr/bin/env bash
# Shared helpers for the git-related Claude Code hooks. Sourced by
# pre-push-review-gate.sh and codify-prompt.sh so the parsing lives in one place.

# Commands that run another command (and may change its cwd or environment first,
# e.g. `env -C dir`, `builtin cd`). Pushes behind them are detected but never resolved.
_GIT_CMD_WRAPPERS="env command builtin nohup time nice sudo exec xargs"
# Shells that take the command as a string (`bash -c "git push"`); any `git`
# followed by `push` in that string counts as a push.
_GIT_CMD_SHELLS="bash sh zsh dash ksh"

# git_push_dir CMD BASE — print the directory the `git push` in CMD runs from,
# starting at BASE (the session cwd). Follows `cd`/`pushd DIR` segments that come
# before the push and `git -C DIR` options (relative paths compose, as git does).
# Returns 1 when CMD has no push, 2 when the target cannot be resolved statically
# so callers can fail closed: subshells, groups, expansions, --git-dir/--work-tree,
# GIT_DIR/GIT_WORK_TREE, cd options or a bare pushd, a cd whose effect is unclear
# (inside a pipeline, backgrounded, or in a command with quoting the splitter
# ignores), commands that move/replace the shell, a push behind a wrapper, or
# several pushes that resolve to different directories.
git_push_dir() {
  local cmd="$1" dir="$2" seg norm found="" rest unsure_cd=0
  is_git_push "$cmd" || return 1
  [[ "$cmd" =~ [\(\)\{\}\$\`] ]] && return 2
  [[ "$cmd" == *GIT_DIR=* || "$cmd" == *GIT_WORK_TREE=* ]] && return 2
  # A cd only moves the push when the two are plain sequential commands: not in a
  # pipeline stage, not backgrounded, and not inside quotes this splitter ignores.
  rest="${cmd//&&/}"; rest="${rest//||/}"
  [[ "$rest" == *[\|\&\"\']* ]] && unsure_cd=1
  norm="${cmd//&&/$'\n'}"; norm="${norm//||/$'\n'}"
  norm="${norm//;/$'\n'}"; norm="${norm//|/$'\n'}"; norm="${norm//&/$'\n'}"
  while IFS= read -r seg; do
    while [[ "$seg" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=(\"[^\"]*\"|\'[^\']*\'|[^[:space:]]*)([[:space:]]+|$) ]]; do
      seg="${seg#"${BASH_REMATCH[0]}"}"
    done
    local toks; read -ra toks <<<"$seg"
    case "${toks[0]:-}" in
      cd|pushd)
        [[ $unsure_cd -eq 0 ]] || return 2
        if [[ "${toks[0]}" == pushd && -z "${toks[1]:-}" ]]; then return 2; fi   # swaps the stack
        _git_cmd_resolve "$dir" "${toks[1]:-$HOME}" || return 2
        dir="$_git_cmd_resolved"; continue;;
      popd|eval|source|.|export) return 2;;
      git) ;;
      "") continue;;
      *)
        if [[ " $_GIT_CMD_WRAPPERS $_GIT_CMD_SHELLS " == *" ${toks[0]} "* ]]; then
          # A wrapper is harmless unless it hides the push or a directory change.
          is_git_push "$seg" && return 2
          [[ " ${toks[*]} " =~ [[:space:]](cd|pushd|popd)[[:space:]] ]] && return 2
        fi
        continue;;
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
    # Every push must land in one place; the gate checks a single repository.
    [[ -z "$found" || "$found" == "$d" ]] || return 2
    found="$d"
  done <<<"$norm"
  [[ -n "$found" ]] || return 1
  printf '%s\n' "$found"
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
  local cmd="$1" seg norm cmd_meta=0
  local meta="[][\$\`\\\\\"'(){}*?~<]"
  # Check the whole command before splitting: the split below drops grouping
  # characters, and `--dry-run {--no-dry-run,origin}` must not lose its braces.
  [[ "$cmd" =~ $meta ]] && cmd_meta=1
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
    # A shell given a command string (`-c`, `-lc`, ...): any `git` followed later by
    # `push` is a push. A shell running a script file is not inspected.
    if [[ " $_GIT_CMD_SHELLS " == *" ${toks[0]:-} "* ]]; then
      [[ " ${toks[*]} " =~ [[:space:]]-[A-Za-z]*c[A-Za-z]*[[:space:]] && "$raw" == *git*push* ]] && return 0
      continue
    fi
    # A wrapper (env/command/nohup/...) can carry its own options and values before
    # `git`; find the `git` token, skip its global options, and count the segment as
    # a push when the subcommand is `push` — with no dry-run exemption (fail closed).
    if [[ " $_GIT_CMD_WRAPPERS " == *" ${toks[0]:-} "* ]]; then
      local k=1
      while [[ $k -lt ${#toks[@]} && "${toks[$k]}" != git ]]; do k=$((k+1)); done
      k=$((k+1))
      while [[ $k -lt ${#toks[@]} && "${toks[$k]}" == -* ]]; do
        case "${toks[$k]}" in
          -C|-c|--git-dir|--work-tree|--namespace|--exec-path) k=$((k+2));;
          *) k=$((k+1));;
        esac
      done
      [[ "${toks[$k]:-}" == push ]] && return 0
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
    # One invariant for the whole command, not per region: with no quoting, expansion,
    # grouping or glob characters anywhere (env assignments and git global options
    # included) the shell cannot rewrite what we parsed, so we see what git sees.
    [[ $cmd_meta -eq 1 ]] && unknown=1
    [[ $dry -eq 1 && $unknown -eq 0 ]] && continue
    return 0
  done <<<"$norm"
  return 1
}
