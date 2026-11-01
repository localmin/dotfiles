#!/usr/bin/env bash
# test-render-digest.sh — offline tests for render-digest.py
# Golden outputs live in fixtures/render/expected-*.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/render-digest.py"
FX="$SCRIPT_DIR/fixtures/render"
# No EXIT trap: see test-select-new.sh. TEST_TMPDIR redirects scratch files when
# TMPDIR itself is not writable.
TMPROOT="$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/render-digest-test.XXXXXX")"
if [ -z "$TMPROOT" ] || [ ! -d "$TMPROOT" ]; then
  echo "test-render-digest.sh: mktemp -d failed; set TEST_TMPDIR to a writable directory" >&2
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

assert_same_file() {
  if cmp -s "$2" "$3"; then ok "$1"; else ng "$1" "$(basename "$2")" "$(diff "$2" "$3" | head -20)"; fi
}

render() {
  "$TARGET" --items "$FX/items.jsonl" --trends "$FX/trends.md" --title "ePrint digest 2026-W44" \
    --picks "${PICKS:-$FX/picks.jsonl}" --glossary "${GLOSSARY:-$FX/glossary.jsonl}" "$@"
}

# Fixture JSONL file $2 with every line rewritten by jq filter $1.
fixture_with() {
  local f="$TMPROOT/fx-$RANDOM.jsonl"
  jq -c "$1" "$2" >"$f"
  echo "$f"
}

# Results fixture with one line rewritten by a jq filter.
results_with() {
  local f="$TMPROOT/results-$RANDOM.jsonl"
  jq -c "$1" "$FX/results.jsonl" >"$f"
  echo "$f"
}

# --- new note -----------------------------------------------------------------------
OUT="$TMPROOT/new.md"
res=$(render --results "$FX/results.jsonl" -o "$OUT")
assert_eq "new: exit 0" "0" "$?"
assert_same_file "new: matches golden" "$FX/expected-new.md" "$OUT"
assert_contains "new: reports counts on stdout" "$res" "total=5"
assert_contains "new: reports pqc count on stdout" "$res" "pqc=3"

# --- same-week append: one heading level down under a dated H2 ------------------------
OUT="$TMPROOT/append.md"
render --results "$FX/results.jsonl" --append-date 2026-10-30 -o "$OUT" >/dev/null
assert_eq "append: exit 0" "0" "$?"
assert_same_file "append: matches golden" "$FX/expected-append.md" "$OUT"

# --- results can arrive split across several batch files ------------------------------
head -2 "$FX/results.jsonl" >"$TMPROOT/r1.jsonl"
tail -n +3 "$FX/results.jsonl" >"$TMPROOT/r2.jsonl"
OUT="$TMPROOT/split.md"
render --results "$TMPROOT/r1.jsonl" "$TMPROOT/r2.jsonl" -o "$OUT" >/dev/null
assert_same_file "split results: same as one file" "$FX/expected-new.md" "$OUT"

# --- no PQC paper ---------------------------------------------------------------------
OUT="$TMPROOT/nopqc.md"
render --results "$(results_with '.pqc = false')" -o "$OUT" >/dev/null
assert_contains "no pqc: count line says 0" "$(cat "$OUT")" "うち PQC 関連 0 件）"
assert_not_contains "no pqc: no PQC marker on picks" "$(cat "$OUT")" "· PQC"

# --- the full list is gone: only picked papers appear ---------------------------------
assert_not_contains "no full list: unpicked paper absent" "$(cat "$TMPROOT/new.md")" "2026/2551"

# --- glossary descriptions are folded onto one list line ------------------------------
OUT="$TMPROOT/fold.md"
GLOSSARY="$(fixture_with 'if .term == "マスキング" then .desc = "一行目\n  二行目" else . end' "$FX/glossary.jsonl")" \
  render --results "$FX/results.jsonl" -o "$OUT" >/dev/null
assert_contains "fold: newline collapsed to a space" "$(cat "$OUT")" "- **マスキング**: 一行目 二行目"

# --- an empty glossary still renders the section --------------------------------------
: >"$TMPROOT/empty.jsonl"
OUT="$TMPROOT/noglossary.md"
GLOSSARY="$TMPROOT/empty.jsonl" render --results "$FX/results.jsonl" -o "$OUT" >/dev/null
assert_contains "empty glossary: says none" "$(cat "$OUT")" $'## 用語解説\n\n- 該当なし'

# --- picks are validated: they are written by an LLM ----------------------------------
expect_pick_reject() {
  local name="$1" picks="$2" needle="$3" out
  out=$(PICKS="$picks" render --results "$FX/results.jsonl" -o "$TMPROOT/rej.md" 2>&1)
  assert_eq "$name: exit 3" "3" "$?"
  assert_contains "$name: names the problem" "$out" "$needle"
}
expect_pick_reject "pick of unknown id" \
  "$(fixture_with 'if .id == "2026/2590" then .id = "2026/9999" else . end' "$FX/picks.jsonl")" "2026/9999"
expect_pick_reject "empty overview" \
  "$(fixture_with 'if .id == "2026/2590" then .overview_ja = "" else . end' "$FX/picks.jsonl")" "2026/2590"
expect_pick_reject "heading inside overview" \
  "$(fixture_with 'if .id == "2026/2590" then .overview_ja = "## 見出し" else . end' "$FX/picks.jsonl")" "2026/2590"
expect_pick_reject "read-verdict marker in overview" \
  "$(fixture_with 'if .id == "2026/2590" then .overview_ja = "読了判定: 後で読む" else . end' "$FX/picks.jsonl")" "読了判定:"
dup="$TMPROOT/dup-picks.jsonl"
cat "$FX/picks.jsonl" >"$dup" && head -1 "$FX/picks.jsonl" >>"$dup"
expect_pick_reject "duplicate pick" "$dup" "2026/2601"
nine="$TMPROOT/nine-picks.jsonl"
for i in 1 2 3 4 5 6 7 8 9; do cat "$FX/picks.jsonl"; done | head -9 >"$nine"
expect_pick_reject "more than 8 picks" "$nine" "8"
expect_pick_reject "no picks" "$TMPROOT/empty.jsonl" "pick"
out=$(GLOSSARY="$(fixture_with '.desc = ""' "$FX/glossary.jsonl")" render --results "$FX/results.jsonl" -o "$TMPROOT/rej.md" 2>&1)
assert_eq "empty glossary desc: exit 3" "3" "$?"
expect_pick_reject "fullwidth read-verdict marker" \
  "$(fixture_with 'if .id == "2026/2590" then .overview_ja = "読了判定：後で読む" else . end' "$FX/picks.jsonl")" "読了判定"

# --- trends are free text from the agent: headings would break the outline -----------
printf -- '- 話題（1 件）: 2026/2590\n## 見出し\n' >"$TMPROOT/trends-heading.md"
out=$("$TARGET" --items "$FX/items.jsonl" --trends "$TMPROOT/trends-heading.md" --title "ePrint digest 2026-W44" \
  --picks "$FX/picks.jsonl" --glossary "$FX/glossary.jsonl" --results "$FX/results.jsonl" -o "$TMPROOT/rej.md" 2>&1)
assert_eq "heading in trends: exit 3" "3" "$?"
assert_contains "heading in trends: names the problem" "$out" "trends"

# --- coverage is enforced: the full list exists so nothing is silently dropped --------
expect_reject() {
  local name="$1" results="$2" needle="$3" out
  out=$(render --results "$results" -o "$TMPROOT/rej.md" 2>&1)
  assert_eq "$name: exit 3" "3" "$?"
  assert_contains "$name: names the problem" "$out" "$needle"
}
expect_reject "missing result" "$(results_with 'select(.id != "2026/2588")')" "2026/2588"
expect_reject "unknown id" "$(results_with 'if .id == "2026/2551" then .id = "2026/9999" else . end')" "2026/9999"
expect_reject "pqc not boolean" "$(results_with 'if .id == "2026/2590" then .pqc = "false" else . end')" "2026/2590"
expect_reject "empty title_ja" "$(results_with 'if .id == "2026/2590" then .title_ja = "" else . end')" "2026/2590"
dup="$TMPROOT/dup.jsonl"
cat "$FX/results.jsonl" >"$dup" && head -1 "$FX/results.jsonl" >>"$dup"
expect_reject "duplicate result" "$dup" "2026/2614"
broken="$TMPROOT/broken.jsonl"
cat "$FX/results.jsonl" >"$broken" && printf '{"id": "2026/26\n' >>"$broken"
expect_reject "broken JSON line" "$broken" "line 6"

# --- a parseable line that is not an object is invalid input, not a crash -------------
for bad in '"oops"' '[1, 2]'; do
  f="$TMPROOT/nonobj-$RANDOM.jsonl"
  cat "$FX/results.jsonl" >"$f" && printf '%s\n' "$bad" >>"$f"
  expect_reject "non-object line $bad" "$f" "line 6"
done

# --- weekly-review must never pick this note up ---------------------------------------
expect_reject "read-verdict marker" \
  "$(results_with 'if .id == "2026/2590" then .summary_ja = "読了判定: 後で読む" else . end')" "読了判定:"
out=$(render --results "$FX/results.jsonl" --title "inbox 2026-10-26" -o "$TMPROOT/t.md" 2>&1)
assert_eq "title: inbox-like title rejected" "2" "$?"

rm -rf "$TMPROOT"
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
