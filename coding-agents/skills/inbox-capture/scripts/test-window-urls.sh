#!/usr/bin/env bash
# test-window-urls.sh — offline tests for list-windows.sh / window-urls.sh
# osascript is stubbed via PATH, so no Chrome / Apple Events are needed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# TEST_TMPDIR lets a caller redirect scratch files when TMPDIR itself is not writable.
TMPROOT="$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/window-urls-test.XXXXXX")"
if [ -z "$TMPROOT" ] || [ ! -d "$TMPROOT" ]; then
  echo "test-window-urls.sh: mktemp -d failed; set TEST_TMPDIR to a writable directory" >&2
  exit 1
fi

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
ng() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1"
  printf '     expected: %s\n' "$2"
  printf '     actual:   %s\n' "$3"
}

assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else ng "$1" "$2" "$3"; fi
}

assert_contains() {
  case "$2" in
    *"$3"*) ok "$1" ;;
    *) ng "$1" "contains: $3" "$2" ;;
  esac
}

# Stub osascript: append the AppleScript it was given (via -e or stdin) to $STUB_LOG.
# A script addressing "window id" gets $STUB_URLS (exit $STUB_URLS_CODE); anything
# else is treated as the window-list query and gets $STUB_LIST.
mkdir -p "$TMPROOT/bin"
cat >"$TMPROOT/bin/osascript" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "-e" ]; then script="$2"; else script="$(cat)"; fi
printf '%s\n==END==\n' "$script" >>"$STUB_LOG"
case "$script" in
  *"window id"*)
    [ "${STUB_URLS_CODE:-0}" -ne 0 ] && { echo "execution error: no such window (-1728)" >&2; exit "$STUB_URLS_CODE"; }
    printf '%s\n' "$STUB_URLS" ;;
  *) printf '%s\n' "$STUB_LIST" ;;
esac
STUB
chmod +x "$TMPROOT/bin/osascript"

run() {
  # $1: script name, rest: args. Sets OUT / ERR / CODE.
  local name="$1"; shift
  STUB_LOG="$TMPROOT/log-$RANDOM"; : >"$STUB_LOG"; export STUB_LOG
  OUT="$(PATH="$TMPROOT/bin:$PATH" "$SCRIPT_DIR/$name" "$@" 2>"$TMPROOT/err" </dev/null)"
  CODE=$?
  ERR="$(cat "$TMPROOT/err")"
  LOG="$(cat "$STUB_LOG")"
}

export STUB_LIST="1|1347257622|19|Some title"
export STUB_URLS="https://a.example/
https://b.example/"
export STUB_URLS_CODE=0

# --- list-windows.sh ---
run list-windows.sh
assert_eq "list: exit 0" "0" "$CODE"
assert_contains "list: asks Chrome for the stable window id" "$LOG" "id of w"
assert_eq "list: passes the number|id|tabs|title rows through" "$STUB_LIST" "$OUT"

# --- window-urls.sh with a window id ---
run window-urls.sh 1347257622
assert_eq "urls: exit 0" "0" "$CODE"
assert_contains "urls: addresses the window by id, not by index" "$LOG" "window id 1347257622"
assert_contains "urls: prints the tab URLs" "$OUT" "https://b.example/"

# --- non-numeric argument must never reach AppleScript ---
run window-urls.sh '1 then do shell script "x"'
assert_eq "urls: non-numeric id -> exit 2" "2" "$CODE"
assert_eq "urls: non-numeric id -> osascript not called" "" "$LOG"

# --- window closed / id unknown -> fail loudly, mention the id ---
STUB_URLS_CODE=1 run window-urls.sh 42
assert_eq "urls: unknown id -> exit 1" "1" "$CODE"
assert_contains "urls: unknown id -> error names the id" "$ERR" "42"

# --- no argument with a single window -> auto-select by id ---
run window-urls.sh
assert_eq "urls: single window auto-select -> exit 0" "0" "$CODE"
assert_contains "urls: auto-select uses the id column" "$LOG" "window id 1347257622"

rm -rf "$TMPROOT"
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
