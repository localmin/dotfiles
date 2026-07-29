#!/usr/bin/env bash
# test-fetch-batch.sh — offline tests for fetch-batch.sh URL classification.
# Exercises `fetch-batch.sh --plan <url>`, which resolves a URL to a
# "<kind><TAB><command>" plan without performing any network access.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/fetch-batch.sh"

PASS=0
FAIL=0

expect_plan() {
  local url="$1" want="$2"
  local got
  got=$("$TARGET" --plan "$url" 2>&1)
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$url" "$want" "$got"
  fi
}

T=$'\t'

# GitHub family — every path must resolve to a gh command, never to ax.
expect_plan 'https://github.com/openai/codex-security' \
  "github${T}gh api repos/openai/codex-security/readme --jq .content"
expect_plan 'https://github.com/openai/codex-security/' \
  "github${T}gh api repos/openai/codex-security/readme --jq .content"
expect_plan 'https://github.com/o/r/blob/main/src/a.ts' \
  "github${T}gh api repos/o/r/contents/src/a.ts?ref=main --jq .content"
expect_plan 'https://raw.githubusercontent.com/o/r/main/README.md' \
  "github${T}gh api repos/o/r/contents/README.md?ref=main --jq .content"
expect_plan 'https://github.com/o/r/tree/main/docs' \
  "github${T}gh api repos/o/r/contents/docs?ref=main --jq .content"
expect_plan 'https://gist.github.com/someone/abc123' \
  "github${T}gh gist view abc123 -r"
expect_plan 'https://github.com/o/r/issues/42' \
  "github${T}gh issue view 42 --repo o/r"
expect_plan 'https://github.com/o/r/pull/7' \
  "github${T}gh pr view 7 --repo o/r"
expect_plan 'https://github.com/o/r/releases/tag/v1.0.0' \
  "github${T}gh release view v1.0.0 --repo o/r"
expect_plan 'https://github.com/o/r/discussions/5' \
  "github${T}gh api repos/o/r/discussions/5"
# Unmapped github-owned path still falls back to gh, never WebFetch/ax.
expect_plan 'https://github.com/o/r/wiki/Home' \
  "github${T}gh api repos/o/r/readme --jq .content"
expect_plan 'https://github.com/openai' \
  "github${T}gh api users/openai"
expect_plan 'https://github.com/o/r/releases' \
  "github${T}gh api repos/o/r/readme --jq .content"

# Query strings and fragments must not leak into the resolved path.
expect_plan 'https://github.com/o/r/blob/main/src/a.ts#L10' \
  "github${T}gh api repos/o/r/contents/src/a.ts?ref=main --jq .content"
expect_plan 'https://github.com/o/r/issues/42?foo=bar' \
  "github${T}gh issue view 42 --repo o/r"

# PDF is decided by the URL suffix here; content-type sniffing happens at fetch time.
expect_plan 'https://example.com/docs/paper.pdf' \
  "pdf${T}ax https://example.com/docs/paper.pdf -m 10 -o"
expect_plan 'https://example.com/docs/paper.PDF' \
  "pdf${T}ax https://example.com/docs/paper.PDF -m 10 -o"

# Everything else is HTML via ax --md. --all must always be present: without it
# ax stops at 50 blocks and --budget cannot lift that cap, silently dropping the
# tail of long articles.
expect_plan 'https://zenn.dev/notahotel/articles/0c28638945aa32' \
  "html${T}ax https://zenn.dev/notahotel/articles/0c28638945aa32 --md --all -m 10 --budget 6000"
expect_plan 'https://www.the-chara.com/view/search?search_category=ct4800' \
  "html${T}ax https://www.the-chara.com/view/search?search_category=ct4800 --md --all -m 10 --budget 6000"
# A .pdf appearing in the query string must not be mistaken for a PDF URL.
expect_plan 'https://example.com/view?file=paper.pdf' \
  "html${T}ax https://example.com/view?file=paper.pdf --md --all -m 10 --budget 6000"

# --- heading extraction (offline; feeds the manifest title column) ---------

expect_heading() {
  local body="$1" want="$2"
  local tmp got
  tmp="$(mktemp "${TMPDIR:-/tmp}/heading.XXXXXX")"
  printf '%s' "$body" >"$tmp"
  got=$("$TARGET" --heading "$tmp" 2>&1)
  rm -f "$tmp"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL heading\n  want: [%s]\n  got:  [%s]\n' "$want" "$got"
  fi
}

expect_heading '# Codex Security

`@openai/codex-security` is a CLI.' 'Codex Security'
# Deeper levels count too — gh output for an issue may not start at h1.
expect_heading '## Some Title

body' 'Some Title'
# Leading blank lines and front matter noise must not hide the heading.
expect_heading '

# Late Heading' 'Late Heading'
# No heading at all yields empty, so the caller knows to fall back.
expect_heading 'just a paragraph with no heading' ''
# Only the first heading wins.
expect_heading '# First
# Second' 'First'
# A tab inside a heading would break the TSV manifest, so it is neutralised.
expect_heading '# Tab	Inside' 'Tab Inside'
# Trailing whitespace and trailing #s are trimmed.
expect_heading '#   Padded Title   ' 'Padded Title'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
