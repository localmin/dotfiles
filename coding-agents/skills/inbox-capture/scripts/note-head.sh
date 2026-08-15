#!/usr/bin/env bash
# note-head.sh — read an Inkdrop note over the MCP stdio route and report only its metadata.
#
# The note body is written to <outdir>/body.md and is never printed, so a large note
# (the daily inbox note passes 60,000 characters) can be identified and appended to
# without ever entering the agent's context.
#
# Usage: note-head.sh [-o <outdir>] [--expect-title <title>] <noteId>
#
# Output (stdout, one key=value per line): id, rev, title, chars, body_path
#
# Exit codes:
#   0  success (and, with --expect-title, the title matched)
#   2  usage error
#   3  the note exists but its title differs from --expect-title (stale cache)
#   4  the note does not exist (404 / not_found) — a cached id may be discarded
#   5  the call did not complete (transport, auth, timeout) — do NOT discard a cached id

set -uo pipefail

OUT_DIR=""
EXPECT_TITLE=""
NOTE_ID=""

usage() {
  echo "usage: note-head.sh [-o <outdir>] [--expect-title <title>] <noteId>" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    -o) [ $# -ge 2 ] || usage; OUT_DIR="$2"; shift 2 ;;
    --expect-title) [ $# -ge 2 ] || usage; EXPECT_TITLE="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) [ -z "$NOTE_ID" ] || usage; NOTE_ID="$1"; shift ;;
  esac
done

case "$NOTE_ID" in
  note:?*) ;;
  *) usage ;;
esac

if [ -z "$OUT_DIR" ]; then
  OUT_DIR="${TMPDIR:-/tmp}/inbox-capture-note"
fi
mkdir -p "$OUT_DIR" || exit 5

RAW="$OUT_DIR/read-note.raw"
ERR="$OUT_DIR/read-note.err"
BODY="$OUT_DIR/body.md"

# The MCP invocation is overridable so the tests can stub it without touching
# the network or triggering a 1Password prompt.
DEFAULT_MCP_CMD="op run --env-file=$HOME/dotfiles/coding-agents/inkdrop.op.env -- npx --prefer-offline -y @inkdropapp/mcp-server"
MCP_CMD="${INKDROP_MCP_CMD:-$DEFAULT_MCP_CMD}"

REQUEST="$(jq -nc --arg id "$NOTE_ID" \
  '{jsonrpc:"2.0", id:1, method:"tools/call",
    params:{name:"read-note", arguments:{noteId:$id}}}')" || exit 5

printf '%s\n' "$REQUEST" | $MCP_CMD >"$RAW" 2>"$ERR"

# Pull the first JSON-RPC object carrying a result or an error. npx and op can write
# unrelated chatter, so fall back to scanning line by line.
ENVELOPE="$(jq -c 'select(type == "object" and (has("result") or has("error")))' <"$RAW" 2>/dev/null | head -1)"
if [ -z "$ENVELOPE" ]; then
  while IFS= read -r line; do
    case "$line" in
      \{*)
        candidate="$(printf '%s' "$line" | jq -c 'select(type == "object" and (has("result") or has("error")))' 2>/dev/null)"
        if [ -n "$candidate" ]; then ENVELOPE="$candidate"; break; fi
        ;;
    esac
  done <"$RAW"
fi

fail_transport() {
  echo "note-head.sh: the read-note call did not complete: $1" >&2
  echo "note-head.sh: raw output: $RAW  stderr: $ERR" >&2
  echo "note-head.sh: a cached note id must NOT be discarded on this failure" >&2
  exit 5
}

[ -n "$ENVELOPE" ] || fail_transport "no JSON-RPC response"

# An error can arrive either as a JSON-RPC error or as an MCP tool result with isError.
ERR_TEXT="$(printf '%s' "$ENVELOPE" | jq -r '
  if has("error") then (.error.message // (.error | tostring))
  elif (.result.isError == true) then ([.result.content[]?.text] | join(" "))
  else empty end' 2>/dev/null)"

if [ -n "$ERR_TEXT" ]; then
  case "$(printf '%s' "$ERR_TEXT" | tr '[:upper:]' '[:lower:]')" in
    *not_found*|*"not found"*|*404*|*missing*|*deleted*)
      echo "note-head.sh: the note does not exist: $ERR_TEXT" >&2
      exit 4
      ;;
  esac
  fail_transport "$ERR_TEXT"
fi

NOTE_JSON="$(printf '%s' "$ENVELOPE" | jq -r '.result.content[0].text // empty' 2>/dev/null)"
[ -n "$NOTE_JSON" ] || fail_transport "the response carried no note payload"

# Write the body straight to disk; it must not pass through stdout.
printf '%s' "$NOTE_JSON" | jq -j '.body // ""' >"$BODY" 2>/dev/null || fail_transport "the note payload was not valid JSON"

ID="$(printf '%s' "$NOTE_JSON" | jq -r '._id // ""')"
REV="$(printf '%s' "$NOTE_JSON" | jq -r '._rev // ""')"
TITLE="$(printf '%s' "$NOTE_JSON" | jq -r '.title // ""')"
BOOK_ID="$(printf '%s' "$NOTE_JSON" | jq -r '.bookId // ""')"
CHARS="$(wc -m <"$BODY" | tr -d ' ')"

printf 'id=%s\n' "$ID"
printf 'rev=%s\n' "$REV"
printf 'title=%s\n' "$TITLE"
printf 'bookId=%s\n' "$BOOK_ID"
printf 'chars=%s\n' "$CHARS"
printf 'body_path=%s\n' "$BODY"

if [ -n "$EXPECT_TITLE" ] && [ "$TITLE" != "$EXPECT_TITLE" ]; then
  echo "note-head.sh: title mismatch — expected '$EXPECT_TITLE', got '$TITLE'" >&2
  echo "note-head.sh: the cached id points at another day's note; discard it and search instead" >&2
  exit 3
fi

exit 0
