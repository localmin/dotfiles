#!/usr/bin/env bash
# test-fetch-feeds.sh — offline tests for fetch-feeds.sh
# ax is stubbed via EPRINT_AX_CMD, so no network access is used.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/fetch-feeds.sh"
# No EXIT trap: see test-select-new.sh. TEST_TMPDIR redirects scratch files when
# TMPDIR itself is not writable.
TMPROOT="$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/fetch-feeds-test.XXXXXX")"
if [ -z "$TMPROOT" ] || [ ! -d "$TMPROOT" ]; then
  echo "test-fetch-feeds.sh: mktemp -d failed; set TEST_TMPDIR to a writable directory" >&2
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

# Stub ax: `ax <url> -m <sec> -o <path>`. Mimics real ax, which exits 0 and saves
# the body even on HTTP errors, reporting the status only in its JSON.
# STUB_404=<CAT> answers 404 for that category, STUB_DOWN=<CAT> fails the transport.
STUB="$TMPROOT/ax-stub.sh"
cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
url="$1"; out=""
while [ $# -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done
cat="${url##*category=}"
printf '%s\n' "$url" >>"$STUB_LOG"
if [ "$cat" = "${STUB_DOWN:-}" ]; then echo "ax: fetch failed: connection reset" >&2; exit 1; fi
if [ "$cat" = "${STUB_404:-}" ]; then
  printf '<html>not found</html>' >"$out"
  printf '{"status": 404, "ok": false, "saved": "%s"}\n' "$out"; exit 0
fi
printf '<rss><channel><title>%s</title></channel></rss>' "$cat" >"$out"
[ -n "${STUB_WARN:-}" ] && echo "ax: warning: slow response" >&2
printf '{"status": 200, "ok": true, "saved": "%s"}\n' "$out"
EOF
chmod +x "$STUB"
export EPRINT_AX_CMD="$STUB"
export STUB_LOG="$TMPROOT/urls.log"

ALL="PROTOCOLS FOUNDATIONS PUBLICKEY ATTACKS IMPLEMENTATION APPLICATIONS SECRETKEY"

# --- all feeds succeed --------------------------------------------------------------
OUT="$TMPROOT/ok"
res=$("$TARGET" -o "$OUT")
assert_eq "all ok: exit 0" "0" "$?"
for c in $ALL; do
  assert_contains "all ok: $c.xml saved" "$(cat "$OUT/$c.xml" 2>/dev/null)" "<title>$c</title>"
done
assert_eq "all ok: one status line per category" "7" "$(printf '%s\n' "$res" | grep -c $'\tok')"
assert_contains "all ok: uses the recent-order category URL" "$(cat "$STUB_LOG")" \
  "https://eprint.iacr.org/rss/rss.xml?order=recent&category=PUBLICKEY"
assert_eq "all ok: no .part files left" "" "$(ls "$OUT" | grep '\.part$')"

# --- a stderr warning on success must not corrupt the JSON status check -------------
OUT="$TMPROOT/warn"
res=$(STUB_WARN=1 "$TARGET" -o "$OUT")
assert_eq "stderr warning: exit 0" "0" "$?"
assert_eq "stderr warning: all feeds ok" "7" "$(printf '%s\n' "$res" | grep -c $'\tok')"

# --- HTTP error: ax exits 0, so the JSON status must be checked ---------------------
OUT="$TMPROOT/404"
res=$(STUB_404=ATTACKS "$TARGET" -o "$OUT")
assert_eq "404: exit 1" "1" "$?"
assert_contains "404: reported as failed" "$res" $'ATTACKS\tfailed'
[ ! -e "$OUT/ATTACKS.xml" ] && ok "404: error page not saved as ATTACKS.xml" \
  || ng "404: error page not saved as ATTACKS.xml" "absent" "present"
assert_contains "404: ax output kept in .err" "$(cat "$OUT/ATTACKS.err" 2>/dev/null)" '"status": 404'
assert_contains "404: other feeds still fetched" "$(cat "$OUT/SECRETKEY.xml" 2>/dev/null)" "SECRETKEY"

# --- transport failure ----------------------------------------------------------------
OUT="$TMPROOT/down"
res=$(STUB_DOWN=PROTOCOLS "$TARGET" -o "$OUT")
assert_eq "down: exit 1" "1" "$?"
assert_contains "down: reported as failed" "$res" $'PROTOCOLS\tfailed'
assert_contains "down: stderr kept in .err" "$(cat "$OUT/PROTOCOLS.err" 2>/dev/null)" "connection reset"

# --- stale file from an earlier run must not survive a failed refetch ---------------
OUT="$TMPROOT/stale"
mkdir -p "$OUT" && printf '<rss>old</rss>' >"$OUT/ATTACKS.xml"
STUB_404=ATTACKS "$TARGET" -o "$OUT" >/dev/null
[ ! -e "$OUT/ATTACKS.xml" ] && ok "stale: previous ATTACKS.xml removed on failure" \
  || ng "stale: previous ATTACKS.xml removed on failure" "absent" "$(cat "$OUT/ATTACKS.xml")"

# --- usage ----------------------------------------------------------------------------
"$TARGET" >/dev/null 2>&1
assert_eq "usage: missing -o exits 2" "2" "$?"

rm -rf "$TMPROOT"
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
