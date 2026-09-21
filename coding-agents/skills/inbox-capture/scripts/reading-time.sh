#!/usr/bin/env bash
# Estimate reading time for inbox daily notes and stamp it into the note head.
#
#   estimate [-p MIN_PER_PDF_PAGE] FILE...
#       Print the estimated minutes (integer, rounded up) needed to read FILEs.
#       Text files are counted as CJK characters + latin words; .pdf files are
#       counted by page.
#
#   apply --summary MIN --articles MIN --count N BODY_FILE
#       Insert or update the "推定読了時間" line right below the note title in
#       BODY_FILE. An existing line is ADDED TO, not replaced, so a second
#       capture on the same day accumulates.
set -euo pipefail

CJK_CPM=500 # CJK characters per minute
EN_WPM=250  # latin words per minute
PDF_MPP=2   # minutes per PDF page

die() {
  echo "reading-time.sh: $*" >&2
  exit 2
}

numeric_or_empty() {
  case "$1" in
  '' | *[!0-9]*) echo '' ;;
  *) echo "$1" ;;
  esac
}

pdf_pages() {
  local file=$1 pages
  # pdfinfo reads the page tree properly, including PDF 1.5+ files that keep page
  # objects in compressed object streams. mdls only answers for Spotlight-indexed
  # locations (never $TMPDIR, where fetch-batch.sh writes), and the raw-byte scan
  # misses those compressed page trees -- both are fallbacks, not the primary.
  pages=$(numeric_or_empty "$(pdfinfo "$file" 2>/dev/null | awk '/^Pages:/ { print $2; exit }')")
  [ -n "$pages" ] ||
    pages=$(numeric_or_empty "$(mdls -raw -name kMDItemNumberOfPages "$file" 2>/dev/null || true)")
  [ -n "$pages" ] ||
    pages=$(numeric_or_empty "$(perl -0777 -ne 'my $n = () = /\/Type\s*\/Page[^s]/g; print $n' "$file" 2>/dev/null || true)")
  # Never fall through to 0: a silent 0 drops the PDF from the stamped total while
  # the command still looks successful.
  [ -n "$pages" ] && [ "$pages" -gt 0 ] ||
    die "page count unknown for $file (install poppler for pdfinfo, or pass the pages yourself)"
  echo "$pages"
}

count_text() {
  # prints "<cjk chars> <latin words>"
  perl -CSD -ne '
    s{https?://\S+}{}g;
    $cjk += () = /[\p{Han}\p{Hiragana}\p{Katakana}\p{InCJKSymbolsAndPunctuation}\p{Hangul}]/g;
    $en  += () = /[A-Za-z0-9]+(?:[\x27\x{2019}-][A-Za-z0-9]+)*/g;
    END { printf "%d %d\n", $cjk + 0, $en + 0 }
  ' "$1"
}

cmd_estimate() {
  while [ $# -gt 0 ]; do
    case "$1" in
    -p)
      [ $# -ge 2 ] || die "-p needs a value"
      PDF_MPP=$2
      shift 2
      ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
    esac
  done
  # An empty set is legitimate: a day where every article was judged 即読了, or
  # where every fetch failed, contributes no article minutes.
  if [ $# -eq 0 ]; then
    echo 0
    return 0
  fi

  local total=0 file cjk en pages
  for file in "$@"; do
    [ -f "$file" ] || die "no such file: $file"
    case "$file" in
    *.pdf)
      # Assign first: pdf_pages' die would only kill the subshell inside awk -v.
      pages=$(pdf_pages "$file") || exit $?
      total=$(awk -v t="$total" -v p="$pages" -v m="$PDF_MPP" 'BEGIN { print t + p * m }')
      ;;
    *)
      read -r cjk en <<EOF
$(count_text "$file")
EOF
      total=$(awk -v t="$total" -v c="${cjk:-0}" -v w="${en:-0}" -v cpm="$CJK_CPM" -v wpm="$EN_WPM" \
        'BEGIN { print t + c / cpm + w / wpm }')
      ;;
    esac
  done
  awk -v t="$total" 'BEGIN { m = int(t); if (t > m) m++; if (m < 1 && t > 0) m = 1; print m }'
}

cmd_apply() {
  local summary='' articles='' count='' body='' v
  while [ $# -gt 0 ]; do
    case "$1" in
    --summary)
      [ $# -ge 2 ] || die "--summary needs a value"
      summary=$2
      shift 2
      ;;
    --articles)
      [ $# -ge 2 ] || die "--articles needs a value"
      articles=$2
      shift 2
      ;;
    --count)
      [ $# -ge 2 ] || die "--count needs a value"
      count=$2
      shift 2
      ;;
    -*) die "unknown option: $1" ;;
    *)
      body=$1
      shift
      ;;
    esac
  done
  for v in "$summary" "$articles" "$count"; do
    case "$v" in
    '' | *[!0-9]*) die "apply needs --summary/--articles/--count as non-negative integers" ;;
    esac
  done
  [ -n "$body" ] && [ -f "$body" ] || die "apply needs an existing body file"

  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/reading-time.XXXXXX") || die "cannot create a temp file"
  perl -CSD -s -e '
    use utf8;
    my ($sum, $art, $cnt) = ($S + 0, $A + 0, $C + 0);
    my @lines = <STDIN>;
    my $idx = -1;
    for my $i (0 .. $#lines) {
      next unless $lines[$i] =~ /^> 推定読了時間:/;
      $idx = $i;
      my @n = $lines[$i] =~ /(\d+)/g;   # total, summary, articles, count
      $sum += $n[1] || 0;
      $art += $n[2] || 0;
      $cnt += $n[3] || 0;
      last;
    }
    my $line = sprintf("> 推定読了時間: 約 %d 分（要約 %d 分 + 記事 %d 分 / %d 本）\n",
                       $sum + $art, $sum, $art, $cnt);
    if ($idx >= 0) {
      $lines[$idx] = $line;
    } else {
      my $at = 0;
      for my $i (0 .. $#lines) {
        if ($lines[$i] =~ /^# /) { $at = $i + 1; last }
      }
      splice(@lines, $at, 0, "\n", $line);
    }
    print @lines;
  ' -- -S="$summary" -A="$articles" -C="$count" <"$body" >"$tmp"
  cat "$tmp" >"$body"
  rm -f "$tmp"
  grep -m1 '^> 推定読了時間:' "$body"
}

case "${1:-}" in
estimate)
  shift
  cmd_estimate "$@"
  ;;
apply)
  shift
  cmd_apply "$@"
  ;;
*)
  die "usage: reading-time.sh estimate [-p MIN] FILE... | reading-time.sh apply --summary N --articles N --count N BODY"
  ;;
esac
