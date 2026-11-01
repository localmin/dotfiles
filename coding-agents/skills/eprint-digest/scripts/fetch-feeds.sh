#!/usr/bin/env bash
# fetch-feeds.sh — download the 7 ePrint category feeds in parallel.
#
# Each category feed holds the 100 most recent papers, so weekly fetching per
# category (at most ~22/week) never overflows, unlike the single all-papers feed.
#
# Usage: fetch-feeds.sh -o <outdir>
#
# Writes <outdir>/<CAT>.xml for every feed that answered 200, and prints one
# "<CAT><TAB>ok|failed<TAB><bytes>" line per category. On failure the ax output is
# kept in <outdir>/<CAT>.err and no <CAT>.xml is left behind, so select-new.py stops
# with exit 3 instead of reading an error page or a stale feed.
#
# Exit codes: 0 all feeds fetched / 1 at least one failed / 2 usage error
#
# EPRINT_AX_CMD overrides the ax binary (tests stub it).

set -uo pipefail

CATEGORIES="PROTOCOLS FOUNDATIONS PUBLICKEY ATTACKS IMPLEMENTATION APPLICATIONS SECRETKEY"
BASE_URL="https://eprint.iacr.org/rss/rss.xml?order=recent&category="
TIMEOUT=20
AX="${EPRINT_AX_CMD:-ax}"
OUT_DIR=""

usage() {
  echo "usage: fetch-feeds.sh -o <outdir>" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    -o) [ $# -ge 2 ] || usage; OUT_DIR="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$OUT_DIR" ] || usage
mkdir -p "$OUT_DIR" || exit 1

fetch_one() {
  local cat="$1" xml="$OUT_DIR/$1.xml" part="$OUT_DIR/$1.xml.part"
  local json="$OUT_DIR/$1.json" err="$OUT_DIR/$1.err"
  rm -f "$xml" "$part" "$json" "$err"
  # ax exits 0 even on HTTP errors and saves the error body; only its JSON "ok"
  # tells success apart, so both the exit code and that field must pass. stderr is
  # kept apart so a warning line cannot make the JSON unparseable.
  if "$AX" "$BASE_URL$cat" -m "$TIMEOUT" -o "$part" >"$json" 2>"$err" \
    && jq -e '.ok == true' "$json" >/dev/null 2>&1 \
    && [ -s "$part" ]; then
    mv "$part" "$xml"
    rm -f "$json" "$err"
  else
    cat "$json" >>"$err"
    rm -f "$part" "$json"
  fi
}

pids=""
for c in $CATEGORIES; do
  fetch_one "$c" &
  pids="$pids $!"
done
for p in $pids; do wait "$p"; done

status=0
for c in $CATEGORIES; do
  if [ -s "$OUT_DIR/$c.xml" ]; then
    printf '%s\tok\t%s\n' "$c" "$(wc -c <"$OUT_DIR/$c.xml" | tr -d ' ')"
  else
    printf '%s\tfailed\t0\n' "$c"
    status=1
  fi
done
exit "$status"
