#!/usr/bin/env bash
# Regression tests for pre-push-review-gate.sh: the gate must judge the repository
# the push actually targets, not the repository the hook process happens to run in.
#
# Guarantees: a push redirected with `git -C <dir>` or a preceding `cd <dir> &&`
# is gated against <dir> (relative paths resolve against the session cwd); a push
# whose target cannot be resolved statically (subshell grouping, expansions) is
# blocked rather than allowed.
# Does not guarantee: is_git_push edge cases (covered by its own design notes),
# ast-grep gate behaviour, or the docs-only / review-size logic.
#
# Usage: bash test-pre-push-review-gate.sh   (offline; set TEST_TMPDIR if $TMPDIR is not writable.
# Under the Claude Code sandbox, macOS bash 3.2 cannot create here-string temp files
# unless the cwd is writable — run it from a writable directory.)
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pre-push-review-gate.sh"
T="$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/prepush-test.XXXXXX")"

mkrepo() {  # mkrepo <dir> <reviewed: yes|no>
  local d="$1" bare="$1.remote.git"
  git init -q -b main "$d"; git -C "$d" config user.email t@example.invalid; git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
  echo 'echo hi' > "$d/a.sh"; git -C "$d" add a.sh; git -C "$d" commit -qm init
  git init -q --bare "$bare"; git -C "$d" remote add origin "$bare"; git -C "$d" push -q -u origin main
  echo 'echo changed' > "$d/a.sh"; git -C "$d" commit -qam change
  if [[ "$2" == yes ]]; then git -C "$d" rev-parse HEAD > "$d/.git/review-ok"; fi
}
mkrepo "$T/approved" yes
mkrepo "$T/pending" no

pass=0 fail=0
check() {  # check <name> <expect: allow|block> <session cwd> <command>
  local name="$1" expect="$2" cwd="$3" cmd="$4" rc got
  jq -nc --arg c "$cmd" --arg d "$cwd" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
    | (cd "$cwd" && bash "$HOOK" >/dev/null 2>&1); rc=$?
  [[ $rc -eq 0 ]] && got=allow || got=block
  if [[ "$got" == "$expect" ]]; then pass=$((pass+1)); echo "PASS $name"
  else fail=$((fail+1)); echo "FAIL $name: expected $expect, got $got (rc=$rc)"; fi
}

check "plain push in reviewed repo"            allow "$T/approved" "git push"
check "plain push in unreviewed repo"          block "$T/pending"  "git push"
check "-C into unreviewed repo"                block "$T/approved" "git -C $T/pending push"
check "cd into unreviewed repo"                block "$T/approved" "cd $T/pending && git push"
check "relative -C against session cwd"        block "$T"          "git -C pending push"
check "-C into reviewed repo from unreviewed"  allow "$T/pending"  "git -C $T/approved push"
check "subshell grouping fails closed"         block "$T/approved" "(cd $T/pending && git push)"
check "expanded -C target fails closed"        block "$T/approved" 'git -C "$X" push'
check "cd with an option fails closed"         block "$T/approved" "cd -P $T/pending && git push"
check "cd - fails closed"                      block "$T/approved" "cd - && git push"
check "GIT_DIR env fails closed"               block "$T"          "GIT_DIR=$T/pending/.git git push"
check "GIT_DIR env inside a reviewed repo"     block "$T/approved" "GIT_DIR=$T/pending/.git git push"
check "non-repo target fails closed"           block "$T/approved" "git -C $T push"
check "builtin cd fails closed"                block "$T/approved" "builtin cd $T/pending && git push"
check "command cd fails closed"                block "$T/approved" "command cd $T/pending && git push"
check "env-wrapped push is gated"              block "$T/pending"  "env git push"
check "nohup-wrapped push is gated"            block "$T/pending"  "nohup git push"
check "command-wrapped push is gated"          block "$T/pending"  "command git push"
check "wrapped push in reviewed repo"          block "$T/approved" "env GIT_TRACE=1 git push"
check "ordinary chain before push still works" allow "$T/approved" "git status && echo ok && git push"
check "brace expansion cannot unlock dry-run"  block "$T/pending"  "git push --dry-run {--no-dry-run,origin}"
check "every push in a chain is gated"         block "$T/approved" "git push && git -C $T/pending push"
check "cd in a pipeline does not move the push" block "$T/pending" "cd $T/approved | git push"
check "backgrounded cd does not move the push" block "$T/pending"  "cd $T/approved & git push"
check "quoted cd is not a directory change"    block "$T/pending"  "echo \"a && cd $T/approved && b\" && git push"
check "shell -c wrapper is gated"              block "$T/pending"  "bash -c \"git push\""
check "wrapped non-push git is not a push"     allow "$T/pending"  "env git commit -m push"
check "unrelated wrapper before push is fine"  allow "$T/approved" "command -v jq && git push"
check "shell -c string with separators"        block "$T/pending"  "bash -c \"git fetch; git push\""
check "sh -c string with cd chain"             block "$T/pending"  "sh -c 'cd x && git push'"
check "shell running a script is not a push"   allow "$T/pending"  "bash ./tools/git-push-helper.sh"
check "bare pushd fails closed"                block "$T/approved" "pushd $T/pending; pushd $T/approved; pushd; git push"

echo "passed=$pass failed=$fail (fixtures: $T)"
[[ $fail -eq 0 ]]
