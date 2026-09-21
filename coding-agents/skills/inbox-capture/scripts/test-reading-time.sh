#!/usr/bin/env bash
# Regression test for reading-time.sh. Offline, no MCP, no credentials.
# Override the scratch location with TEST_TMPDIR when TMPDIR is not writable.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
rt="$here/reading-time.sh"
work=$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/test-reading-time.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT

pass=0
fail=0

check() {
  local name=$1 want=$2 got=$3
  if [ "$want" = "$got" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name"
    echo "  want: $want"
    echo "  got : $got"
  fi
}

# --- estimate -----------------------------------------------------------
perl -e 'print "あ" x 1000, "\n"' >"$work/cjk.md"
perl -e 'print "word " x 500, "\n"' >"$work/en.md"
: >"$work/empty.md"
echo "https://example.com/あああああああああああ" >"$work/url.md"

check "estimate: 1000 CJK chars at 500 cpm" "2" "$("$rt" estimate "$work/cjk.md")"
check "estimate: 500 latin words at 250 wpm" "2" "$("$rt" estimate "$work/en.md")"
check "estimate: several files sum up" "4" "$("$rt" estimate "$work/cjk.md" "$work/en.md")"
check "estimate: empty file is 0" "0" "$("$rt" estimate "$work/empty.md")"
check "estimate: URLs are not counted" "0" "$("$rt" estimate "$work/url.md")"

check "estimate: no files is 0, not an error" "0" "$("$rt" estimate)"

"$rt" estimate "$work/missing.md" >/dev/null 2>&1
check "estimate: missing file exits 2" "2" "$?"

# --- estimate: PDFs -----------------------------------------------------
# Minimal two-page PDF; readable both by pdfinfo and by the raw-byte fallback.
cat >"$work/two-pages.pdf" <<'PDF'
%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >> endobj
4 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >> endobj
trailer << /Root 1 0 R >>
%%EOF
PDF

check "estimate: PDF at 2 min/page" "4" "$("$rt" estimate "$work/two-pages.pdf")"
check "estimate: -p overrides min/page" "10" "$("$rt" estimate -p 5 "$work/two-pages.pdf")"

# A PDF no extractor can read must fail loudly rather than count as 0 minutes.
printf 'not a pdf at all\n' >"$work/broken.pdf"
out=$("$rt" estimate "$work/broken.pdf" 2>&1)
status=$?
check "estimate: unreadable PDF exits 2" "2" "$status"
case "$out" in
*"page count unknown"*) pass=$((pass + 1)) ;;
*)
  fail=$((fail + 1))
  echo "FAIL: estimate: unreadable PDF explains itself"
  echo "  got : $out"
  ;;
esac

# --- apply --------------------------------------------------------------
printf '# inbox 2026-09-21\n\n## [title]\n' >"$work/body.md"

check "apply: inserts the line" \
  "> 推定読了時間: 約 42 分（要約 6 分 + 記事 36 分 / 12 本）" \
  "$("$rt" apply --summary 6 --articles 36 --count 12 "$work/body.md")"

check "apply: a second capture accumulates" \
  "> 推定読了時間: 約 54 分（要約 8 分 + 記事 46 分 / 15 本）" \
  "$("$rt" apply --summary 2 --articles 10 --count 3 "$work/body.md")"

check "apply: the line sits under the title" \
  "# inbox 2026-09-21" "$(sed -n '1p' "$work/body.md")"
check "apply: the note body is kept" \
  "## [title]" "$(sed -n '5p' "$work/body.md")"
check "apply: only one line is stamped" \
  "1" "$(grep -c '^> 推定読了時間:' "$work/body.md")"

"$rt" apply --summary x --articles 1 --count 1 "$work/body.md" >/dev/null 2>&1
check "apply: non-numeric minutes exit 2" "2" "$?"

"$rt" apply --articles 1 --count 1 --summary >/dev/null 2>&1
check "apply: a value-less flag exits 2" "2" "$?"

"$rt" apply --summary 1 --articles 1 --count 1 "$work/missing.md" >/dev/null 2>&1
check "apply: missing body exits 2" "2" "$?"

echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
