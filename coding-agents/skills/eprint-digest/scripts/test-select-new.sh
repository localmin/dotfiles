#!/usr/bin/env bash
# test-select-new.sh — offline tests for select-new.py
# Uses the fixture feeds under fixtures/, so no network access is needed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/select-new.py"
FIXTURES="$SCRIPT_DIR/fixtures"
# No EXIT trap: bash runs it inside command-substitution subshells too, which would
# delete TMPROOT partway through the run. Clean up explicitly at the end instead.
# TEST_TMPDIR lets a caller redirect scratch files when TMPDIR itself is not writable
# (e.g. an agent sandbox that denies /var/folders).
TMPROOT="$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/select-new-test.XXXXXX")"
if [ -z "$TMPROOT" ] || [ ! -d "$TMPROOT" ]; then
  echo "test-select-new.sh: mktemp -d failed; set TEST_TMPDIR to a writable directory" >&2
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

# Value of key=value line $2 in output $1
kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

# Fresh copy of the week fixture so a test can modify one feed.
feeds_copy() {
  local d="$TMPROOT/feeds-$RANDOM"
  mkdir -p "$d" && cp "$FIXTURES"/week/*.xml "$d/"
  echo "$d"
}

NOW=2026-10-26T00:00:00Z

# --- initial run (no state): last 7 days by pubDate --------------------------------
OUT="$TMPROOT/initial.jsonl"
STATE="$TMPROOT/none/state.json"
res=$("$TARGET" select --feeds-dir "$FIXTURES/week" --state "$STATE" --now "$NOW" -o "$OUT")
code=$?
assert_eq "initial: exit 0" "0" "$code"
assert_eq "initial: mode is initial" "initial" "$(kv "$res" mode)"
assert_eq "initial: 6 items within 7 days" "6" "$(kv "$res" total)"
assert_eq "initial: max_id is the newest selected" "2026/2614" "$(kv "$res" max_id)"
assert_eq "initial: out path reported" "$OUT" "$(kv "$res" out)"
assert_eq "initial: JSONL has one line per item" "6" "$(wc -l <"$OUT" | tr -d ' ')"
assert_eq "initial: ids grouped by category, ascending within" \
  "2026/2590 2026/2601 2026/2588 2026/2605 2026/2551 2026/2614" \
  "$(jq -r .id "$OUT" | tr '\n' ' ' | sed 's/ $//')"
assert_not_contains "initial: item before the 7-day cutoff is excluded" "$(cat "$OUT")" "2026/2520"
assert_contains "initial: item exactly inside the window is kept" "$(cat "$OUT")" "2026/2551"
assert_eq "initial: count per category" "1" "$(kv "$res" count_PUBLICKEY)"
assert_eq "initial: empty category reports 0" "0" "$(kv "$res" count_APPLICATIONS)"
assert_eq "initial: categories listed in fixed order" \
  "PROTOCOLS FOUNDATIONS PUBLICKEY ATTACKS IMPLEMENTATION APPLICATIONS SECRETKEY" \
  "$(printf '%s\n' "$res" | sed -n 's/^count_\([A-Z]*\)=.*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
assert_not_contains "initial: abstracts never reach stdout" "$res" "abstract."
[ ! -e "$STATE" ] && ok "initial: select does not write state" || ng "initial: select does not write state" "no file" "$STATE exists"

# --- record fields ------------------------------------------------------------------
rec=$(jq -c 'select(.id == "2026/2601")' "$OUT")
assert_eq "record: category code" "PUBLICKEY" "$(printf '%s' "$rec" | jq -r .category)"
assert_eq "record: entity in title decoded" "ML-DSA & Masking: Faster" "$(printf '%s' "$rec" | jq -r .title)"
assert_eq "record: link" "https://eprint.iacr.org/2026/2601" "$(printf '%s' "$rec" | jq -r .link)"
assert_eq "record: CDATA abstract kept verbatim" "We show a < b and a > c for masked ML-DSA." \
  "$(printf '%s' "$rec" | jq -r .abstract)"
assert_eq "record: published as UTC ISO 8601" "2026-10-22T09:00:00Z" "$(printf '%s' "$rec" | jq -r .published)"
assert_eq "record: all authors in order" '["I. Author","J. Author","K. Author"]' \
  "$(jq -c 'select(.id == "2026/2605") | .authors' "$OUT")"

# --- gap warning: a feed whose oldest item is still new cannot prove continuity -----
assert_eq "gap: feeds with every item selected are flagged" "ATTACKS,IMPLEMENTATION" "$(kv "$res" warn_gap)"

# --- incremental run: strictly newer than the stored max ----------------------------
STATE="$TMPROOT/inc/state.json"
mkdir -p "$(dirname "$STATE")"
"$TARGET" commit --state "$STATE" --max-id 2026/2590 >/dev/null
OUT="$TMPROOT/inc.jsonl"
res=$("$TARGET" select --feeds-dir "$FIXTURES/week" --state "$STATE" --now "$NOW" -o "$OUT")
assert_eq "incremental: mode" "incremental" "$(kv "$res" mode)"
assert_eq "incremental: only ids above the stored max" "2026/2601 2026/2605 2026/2614" \
  "$(jq -r .id "$OUT" | sort | tr '\n' ' ' | sed 's/ $//')"
assert_eq "incremental: ignores the 7-day window" "3" "$(kv "$res" total)"

# --- nothing new --------------------------------------------------------------------
"$TARGET" commit --state "$STATE" --max-id 2026/2614 >/dev/null
OUT="$TMPROOT/none.jsonl"
res=$("$TARGET" select --feeds-dir "$FIXTURES/week" --state "$STATE" --now "$NOW" -o "$OUT")
assert_eq "nothing new: exit 0" "0" "$?"
assert_eq "nothing new: total 0" "0" "$(kv "$res" total)"
assert_eq "nothing new: max_id empty" "" "$(kv "$res" max_id)"
assert_eq "nothing new: empty JSONL" "0" "$(wc -l <"$OUT" | tr -d ' ')"

# --- year rollover: compare (year, number), not the number alone --------------------
FEEDS=$(feeds_copy)
cp "$FIXTURES/rollover/SECRETKEY.xml" "$FEEDS/SECRETKEY.xml"
STATE="$TMPROOT/roll/state.json"
mkdir -p "$(dirname "$STATE")"
"$TARGET" commit --state "$STATE" --max-id 2026/2600 >/dev/null
OUT="$TMPROOT/roll.jsonl"
res=$("$TARGET" select --feeds-dir "$FEEDS" --state "$STATE" --now 2027-01-04T00:00:00Z -o "$OUT")
assert_eq "rollover: new-year id is newer than a large old-year id" "2026/2601 2026/2605 2026/2610 2027/0003" \
  "$(jq -r .id "$OUT" | sort | tr '\n' ' ' | sed 's/ $//')"
assert_eq "rollover: max_id is the new-year id" "2027/0003" "$(kv "$res" max_id)"

# --- duplicates across feeds are emitted once ---------------------------------------
FEEDS=$(feeds_copy)
cp "$FIXTURES/week/SECRETKEY.xml" "$FEEDS/FOUNDATIONS.xml"
OUT="$TMPROOT/dup.jsonl"
res=$("$TARGET" select --feeds-dir "$FEEDS" --state "$TMPROOT/dup/none.json" --now "$NOW" -o "$OUT")
assert_eq "duplicate: id appears once" "1" "$(jq -r .id "$OUT" | grep -c '^2026/2614$')"

# --- failure modes: never silently advance past papers we could not read ------------
FEEDS=$(feeds_copy)
mv "$FEEDS/ATTACKS.xml" "$TMPROOT/"
res=$("$TARGET" select --feeds-dir "$FEEDS" --state "$TMPROOT/x/none.json" --now "$NOW" -o "$TMPROOT/miss.jsonl" 2>&1)
assert_eq "missing feed: exit 3" "3" "$?"
assert_contains "missing feed: names the category" "$res" "ATTACKS"

FEEDS=$(feeds_copy)
printf '<html><body>rate limited</body></html' >"$FEEDS/PROTOCOLS.xml"
res=$("$TARGET" select --feeds-dir "$FEEDS" --state "$TMPROOT/x/none.json" --now "$NOW" -o "$TMPROOT/bad.jsonl" 2>&1)
assert_eq "broken feed: exit 3" "3" "$?"
assert_contains "broken feed: names the category" "$res" "PROTOCOLS"

FEEDS=$(feeds_copy)
printf '<?xml version="1.0"?>\n<!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/hosts">]>\n<rss><channel><item><title>&x;</title><link>https://eprint.iacr.org/2026/9999</link><pubDate>Thu, 22 Oct 2026 09:00:00 +0000</pubDate></item></channel></rss>\n' >"$FEEDS/ATTACKS.xml"
res=$("$TARGET" select --feeds-dir "$FEEDS" --state "$TMPROOT/x/none.json" --now "$NOW" -o "$TMPROOT/xxe.jsonl" 2>&1)
assert_eq "external entity: rejected with exit 3" "3" "$?"
assert_not_contains "external entity: file contents never read" "$(cat "$TMPROOT/xxe.jsonl" 2>/dev/null)" "localhost"

FEEDS=$(feeds_copy)
sed '/<item>/,/<\/item>/d' "$FIXTURES/week/ATTACKS.xml" >"$FEEDS/ATTACKS.xml"
res=$("$TARGET" select --feeds-dir "$FEEDS" --state "$TMPROOT/x/none.json" --now "$NOW" -o "$TMPROOT/empty.jsonl" 2>&1)
assert_eq "empty feed: exit 3 (a real category feed is never empty)" "3" "$?"
assert_contains "empty feed: names the category" "$res" "ATTACKS"

FEEDS=$(feeds_copy)
sed 's|https://eprint.iacr.org/2026/2588|javascript:alert(1)//2026/2588|' "$FIXTURES/week/ATTACKS.xml" >"$FEEDS/ATTACKS.xml"
res=$("$TARGET" select --feeds-dir "$FEEDS" --state "$TMPROOT/x/none.json" --now "$NOW" -o "$TMPROOT/link.jsonl" 2>&1)
assert_eq "foreign link: exit 3" "3" "$?"
assert_contains "foreign link: names the category" "$res" "ATTACKS"

# RFC 2822 "-0000" means UTC with unknown origin; Python parses it as a naive datetime.
FEEDS=$(feeds_copy)
sed 's/+0000/-0000/' "$FIXTURES/week/ATTACKS.xml" >"$FEEDS/ATTACKS.xml"
OUT="$TMPROOT/naive.jsonl"
res=$("$TARGET" select --feeds-dir "$FEEDS" --state "$TMPROOT/x/none.json" --now "$NOW" -o "$OUT" 2>&1)
assert_eq "-0000 pubDate: exit 0" "0" "$?"
assert_eq "-0000 pubDate: read as UTC" "2026-10-21T10:00:00Z" "$(jq -r 'select(.id == "2026/2588") | .published' "$OUT")"

STATE="$TMPROOT/corrupt/state.json"
mkdir -p "$(dirname "$STATE")" && printf 'not json' >"$STATE"
res=$("$TARGET" select --feeds-dir "$FIXTURES/week" --state "$STATE" --now "$NOW" -o "$TMPROOT/c.jsonl" 2>&1)
assert_eq "corrupt state: exit 3 (no silent fallback to the 7-day window)" "3" "$?"

# --- commit -------------------------------------------------------------------------
STATE="$TMPROOT/commit/sub/state.json"
res=$("$TARGET" commit --state "$STATE" --max-id 2026/2614)
assert_eq "commit: exit 0" "0" "$?"
assert_eq "commit: creates parent dirs and stores max_id" "2026/2614" "$(jq -r .max_id "$STATE")"
res=$("$TARGET" commit --state "$STATE" --max-id 2026/2500)
assert_eq "commit: older id is a no-op" "2026/2614" "$(jq -r .max_id "$STATE")"
assert_contains "commit: reports unchanged" "$res" "unchanged"
"$TARGET" commit --state "$STATE" --max-id 2027/0001 >/dev/null
assert_eq "commit: newer id across a year boundary advances" "2027/0001" "$(jq -r .max_id "$STATE")"
"$TARGET" commit --state "$STATE" --max-id 'garbage' >/dev/null 2>&1
assert_eq "commit: malformed id is a usage error" "2" "$?"
"$TARGET" commit --state "$STATE" --max-id '' >/dev/null 2>&1
assert_eq "commit: empty id is a usage error" "2" "$?"

# --- usage --------------------------------------------------------------------------
"$TARGET" >/dev/null 2>&1
assert_eq "usage: no subcommand exits 2" "2" "$?"

rm -rf "$TMPROOT"
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
