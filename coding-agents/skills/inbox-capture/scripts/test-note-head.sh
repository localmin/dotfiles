#!/usr/bin/env bash
# test-note-head.sh — offline tests for note-head.sh
# The MCP call is stubbed via INKDROP_MCP_CMD, so no network / 1Password auth is used.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/note-head.sh"
# No EXIT trap: bash runs it inside command-substitution subshells too, which would
# delete TMPROOT partway through the run. Clean up explicitly at the end instead.
# TEST_TMPDIR lets a caller redirect scratch files when TMPDIR itself is not writable
# (e.g. an agent sandbox that denies /var/folders).
TMPROOT="$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/note-head-test.XXXXXX")"
if [ -z "$TMPROOT" ] || [ ! -d "$TMPROOT" ]; then
  echo "test-note-head.sh: mktemp -d failed; set TEST_TMPDIR to a writable directory" >&2
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

assert_not_contains() {
  case "$2" in
    *"$3"*) ng "$1" "must NOT contain: $3" "$2" ;;
    *) ok "$1" ;;
  esac
}

# Build a stub that echoes a canned MCP response on stdout.
# $1: file holding the response, $2: exit code
make_stub() {
  local body_file="$1" code="${2:-0}"
  local stub="$TMPROOT/stub-$RANDOM.sh"
  {
    echo '#!/usr/bin/env bash'
    echo 'cat >/dev/null'   # drain the JSON-RPC request on stdin
    echo "cat '$body_file'"
    echo "exit $code"
  } >"$stub"
  chmod +x "$stub"
  echo "$stub"
}

# A note body long enough that leaking it to stdout would be obvious.
NOTE_BODY='# inbox 2026-08-15

## Some article

- URL: https://example.com
- 読了判定: 即読了

### 要約

本文がここにある。SENTINEL_BODY_MARKER'

# --- fixture: successful read-note ---
SUCCESS_JSON="$TMPROOT/success.json"
jq -nc --arg body "$NOTE_BODY" '
  {jsonrpc:"2.0", id:1, result:{content:[{type:"text", text:(
    {_id:"note:abc123", _rev:"3-deadbeef", title:"inbox 2026-08-15",
     bookId:"book:51GBqxKj", body:$body, status:"active"} | tojson
  )}]}}' >"$SUCCESS_JSON"

# --- fixture: note not found ---
NOTFOUND_JSON="$TMPROOT/notfound.json"
jq -nc '{jsonrpc:"2.0", id:1, result:{isError:true, content:[{type:"text",
  text:"Error: not_found - missing (404)"}]}}' >"$NOTFOUND_JSON"

# --- fixture: transport-level failure (empty output) ---
EMPTY_JSON="$TMPROOT/empty.json"
: >"$EMPTY_JSON"

# === 1. success: metadata on stdout, body only on disk ===
OUT_DIR="$TMPROOT/out1"
STUB="$(make_stub "$SUCCESS_JSON")"
OUTPUT="$(INKDROP_MCP_CMD="$STUB" "$TARGET" -o "$OUT_DIR" note:abc123 2>&1)"
RC=$?
assert_eq "success: exit code 0" "0" "$RC"
assert_contains "success: reports _id" "$OUTPUT" "note:abc123"
assert_contains "success: reports _rev" "$OUTPUT" "3-deadbeef"
assert_contains "success: reports title" "$OUTPUT" "inbox 2026-08-15"
assert_not_contains "success: body is NOT printed" "$OUTPUT" "SENTINEL_BODY_MARKER"

# === 2. success: body file written verbatim ===
if [ -f "$OUT_DIR/body.md" ]; then
  ok "success: body.md exists"
  assert_eq "success: body.md is byte-identical" "$NOTE_BODY" "$(cat "$OUT_DIR/body.md")"
else
  ng "success: body.md exists" "file at $OUT_DIR/body.md" "missing"
  ng "success: body.md is byte-identical" "file" "missing"
fi

# === 3. success: char count reported (wc -m, not bytes) ===
EXPECTED_CHARS="$(printf '%s' "$NOTE_BODY" | wc -m | tr -d ' ')"
assert_contains "success: reports char count" "$OUTPUT" "chars=$EXPECTED_CHARS"

# === 4. --expect-title match ===
OUT_DIR="$TMPROOT/out4"
STUB="$(make_stub "$SUCCESS_JSON")"
INKDROP_MCP_CMD="$STUB" "$TARGET" -o "$OUT_DIR" --expect-title "inbox 2026-08-15" note:abc123 >/dev/null 2>&1
RC=$?
assert_eq "expect-title: matching title exits 0" "0" "$RC"

# === 5. --expect-title mismatch → exit 3 (stale cache, note still exists) ===
OUT_DIR="$TMPROOT/out5"
STUB="$(make_stub "$SUCCESS_JSON")"
OUTPUT="$(INKDROP_MCP_CMD="$STUB" "$TARGET" -o "$OUT_DIR" --expect-title "inbox 2026-08-16" note:abc123 2>&1)"
RC=$?
assert_eq "expect-title: mismatch exits 3" "3" "$RC"
assert_contains "expect-title: mismatch names the actual title" "$OUTPUT" "inbox 2026-08-15"

# === 6. not_found → exit 4 (cache may be discarded) ===
OUT_DIR="$TMPROOT/out6"
STUB="$(make_stub "$NOTFOUND_JSON")"
OUTPUT="$(INKDROP_MCP_CMD="$STUB" "$TARGET" -o "$OUT_DIR" note:gone 2>&1)"
RC=$?
assert_eq "not_found: exits 4" "4" "$RC"

# === 7. transport failure → exit 5 (cache must NOT be discarded) ===
OUT_DIR="$TMPROOT/out7"
STUB="$(make_stub "$EMPTY_JSON" 1)"
OUTPUT="$(INKDROP_MCP_CMD="$STUB" "$TARGET" -o "$OUT_DIR" note:abc123 2>&1)"
RC=$?
assert_eq "transport failure: exits 5" "5" "$RC"
assert_not_contains "transport failure: does not claim not_found" "$OUTPUT" "not_found"

# === 8. missing noteId argument → usage error ===
STUB="$(make_stub "$SUCCESS_JSON")"
OUTPUT="$(INKDROP_MCP_CMD="$STUB" "$TARGET" -o "$TMPROOT/out8" 2>&1)"
RC=$?
assert_eq "usage: missing noteId exits 2" "2" "$RC"

# === 9. noteId without the note: prefix is rejected ===
OUTPUT="$(INKDROP_MCP_CMD="$STUB" "$TARGET" -o "$TMPROOT/out9" abc123 2>&1)"
RC=$?
assert_eq "usage: bare id exits 2" "2" "$RC"

rm -rf "$TMPROOT"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
