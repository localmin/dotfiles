#!/usr/bin/env bash
# fetch-batch.sh — fetch many article URLs concurrently, one file per URL.
#
# The point of this script is to collapse N model round-trips into one. Fetching
# is I/O bound and independent per URL, so every URL is dispatched as a
# background job and the caller pays a single tool call instead of one per URL.
#
# Routing follows the inbox-capture skill: GitHub-owned hosts go through `gh`,
# PDFs are saved with `ax -o` for later paged reading, everything else is read as
# markdown with `ax --md`. Nothing ever falls back to WebFetch.
#
# Usage:
#   fetch-batch.sh [-o OUTDIR] [-b BUDGET] [-j JOBS] [URLFILE]
#   fetch-batch.sh --plan URL
#   fetch-batch.sh --heading FILE
#
#   URLFILE    file with one URL per line; reads stdin when omitted
#   -o OUTDIR  where to write results (default: mktemp -d)
#   -b BUDGET  ax --budget for HTML pages (default: 6000)
#   -j JOBS    max concurrent fetches (default: 8)
#   --plan     print "<kind>\t<command>" for one URL and exit, without fetching
#   --heading  print the first markdown heading of a file (title fallback), then exit
#
# Internal entry points (a github tree plan re-enters the script; also unit-tested):
#   --github-dir OWNER REPO REF PATH  directory listing plus that directory's doc
#   --dir-render PATH JSONFILE        render a contents payload as a listing
#   --dir-doc JSONFILE                name the directory's SKILL.md / README.md
#
# Requires bash 3.2, gh, ax, and jq.
#
# Output: OUTDIR/manifest.tsv with columns idx, kind, status, title, path, url,
# plus one NNN.md / NNN.pdf per URL. The manifest path is echoed on stdout.
# `title` is the page <title> for HTML, else the first markdown heading; it is
# empty only when neither exists, and empty for failed/empty rows.
#
# status values:
#   ok       content fetched, file is non-empty and ax reported no truncation
#   partial  ax reported hidden results — the tail is missing; raise -b and refetch
#   empty    fetch succeeded but produced no content — likely a JS-rendered SPA,
#            so retry with playwright / chrome-devtools (never WebFetch)
#   failed   non-zero exit (4xx / 5xx / timeout / rate limit); see NNN.err
#
# Requires bash 3.2 (macOS default): no associative arrays, no `wait -n`.

set -uo pipefail

BUDGET=6000
JOBS=8
TIMEOUT=10
OUTDIR=""

# Absolute path to this script: a tree plan re-enters it, and the plan may run
# from any working directory.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# Resolution result, set by resolve_plan.
PLAN_KIND=""
PLAN_ARGV=()
PLAN_DECODE=0

# resolve_plan URL — decide how to fetch a URL without touching the network.
resolve_plan() {
  local url="$1"
  local rest host path qpath
  PLAN_KIND=""
  PLAN_ARGV=()
  PLAN_DECODE=0

  rest="${url#*://}"
  host="${rest%%/*}"
  if [ "$rest" = "$host" ]; then path=""; else path="${rest#*/}"; fi
  path="${path%%#*}"
  qpath="${path%%\?*}"
  qpath="${qpath%/}"

  local segs=()
  local IFS_SAVE="$IFS"
  IFS='/'
  # shellcheck disable=SC2206  # deliberate word splitting on /
  segs=($qpath)
  IFS="$IFS_SAVE"

  case "$host" in
    gist.github.com)
      PLAN_KIND=github
      local gid="${segs[$((${#segs[@]} - 1))]}"
      PLAN_ARGV=(gh gist view "$gid" -r)
      return
      ;;
    raw.githubusercontent.com)
      PLAN_KIND=github
      github_contents_plan "${segs[0]}" "${segs[1]}" "${segs[2]}" 3 "${segs[@]}"
      return
      ;;
    github.com | www.github.com)
      PLAN_KIND=github
      github_plan "${segs[@]}"
      return
      ;;
  esac

  case "$qpath" in
    *.pdf | *.PDF | *.Pdf)
      PLAN_KIND=pdf
      PLAN_ARGV=(ax "$url" -m "$TIMEOUT" -o)
      return
      ;;
  esac

  # --all is required, not optional: ax caps at 50 result blocks by default and
  # --budget does not lift that cap, so a long article silently loses its tail
  # (measured: a zenn article returned 1855 bytes at --budget 6000 and at
  # --budget 20000 alike, but 7749 bytes with --all). --budget still bounds the
  # total once the block cap is gone.
  PLAN_KIND=html
  PLAN_ARGV=(ax "$url" --md --all -m "$TIMEOUT" --budget "$BUDGET")
}

# join_segs START SEGS... — rebuild the path that sits below a ref.
join_segs() {
  local start="$1"
  shift
  local segs=("$@")
  local i out=""
  for ((i = start; i < ${#segs[@]}; i++)); do
    if [ -z "$out" ]; then out="${segs[$i]}"; else out="$out/${segs[$i]}"; fi
  done
  printf '%s' "$out"
}

# github_contents_plan OWNER REPO REF FIRST_PATH_INDEX SEGS... — read a file
# through the contents API. The blob is base64, so mark it for decode.
github_contents_plan() {
  local owner="$1" repo="$2" ref="$3" start="$4"
  shift 4
  local filepath
  filepath=$(join_segs "$start" "$@")
  PLAN_ARGV=(gh api "repos/$owner/$repo/contents/$filepath?ref=$ref" --jq .content)
  PLAN_DECODE=1
}

# github_tree_plan OWNER REPO REF FIRST_PATH_INDEX SEGS... — read a directory.
# The same contents endpoint returns an array here, so the blob plan's `--jq
# .content` fails outright ("expected an object but got: array"). Rendering the
# directory takes two API calls, which does not fit the one-command plan model,
# so the plan re-enters this script instead.
github_tree_plan() {
  local owner="$1" repo="$2" ref="$3" start="$4"
  shift 4
  local filepath
  filepath=$(join_segs "$start" "$@")
  if [ -z "$filepath" ]; then
    # A tree URL with no path below the ref is the repo root browse page.
    github_readme_plan "$owner" "$repo"
    return
  fi
  PLAN_ARGV=("$SELF" --github-dir "$owner" "$repo" "$ref" "$filepath")
  PLAN_DECODE=0
}

# dir_render PATH JSONFILE — the contents payload as a markdown listing.
dir_render() {
  printf '# %s\n\n' "$1"
  jq -r 'map("- " + .name + (if .type=="dir" then "/" else "" end)) | join("\n")' "$2"
}

# dir_doc JSONFILE — the directory's own document, if it has one. A bare listing
# of file names carries nothing to summarize, and a directory URL in a browser
# renders this same file below the listing, so it is what the reader is after.
dir_doc() {
  jq -r 'map(select(.type == "file" and (.name | test("^(SKILL|README)\\.(md|markdown)$"; "i")))) | (.[0].name // "")' "$1"
}

# github_dir_fetch OWNER REPO REF PATH — listing plus that directory's document.
github_dir_fetch() {
  local owner="$1" repo="$2" ref="$3" path="$4"
  local json doc
  json="$(mktemp "${TMPDIR:-/tmp}/inbox-dir.XXXXXX")"
  if ! gh api "repos/$owner/$repo/contents/$path?ref=$ref" >"$json"; then
    rm -f "$json"
    return 1
  fi
  dir_render "$path" "$json"
  doc="$(dir_doc "$json")"
  rm -f "$json"
  [ -n "$doc" ] || return 0
  printf '\n\n## %s\n\n' "$doc"
  gh api "repos/$owner/$repo/contents/$path/$doc?ref=$ref" --jq .content | base64 --decode
}

# github_readme_plan OWNER REPO — the default for any github.com path we do not
# map explicitly, so unmapped paths still stay on `gh` instead of leaking to ax.
github_readme_plan() {
  PLAN_ARGV=(gh api "repos/$1/$2/readme" --jq .content)
  PLAN_DECODE=1
}

# github_plan SEGS... — map a github.com path to the closest gh resource.
github_plan() {
  local segs=("$@")
  local n=${#segs[@]}

  if [ "$n" -lt 1 ] || [ -z "${segs[0]}" ]; then
    PLAN_ARGV=(gh api "repos")
    return
  fi
  if [ "$n" -lt 2 ]; then
    PLAN_ARGV=(gh api "users/${segs[0]}")
    return
  fi

  local owner="${segs[0]}" repo="${segs[1]}"
  if [ "$n" -eq 2 ]; then
    github_readme_plan "$owner" "$repo"
    return
  fi

  # Every mapping below needs at least one segment after the type (a ref, an
  # issue number, a tag); without it the path is a listing page, not a resource.
  if [ "$n" -lt 4 ]; then
    github_readme_plan "$owner" "$repo"
    return
  fi

  case "${segs[2]}" in
    blob)
      github_contents_plan "$owner" "$repo" "${segs[3]}" 4 "${segs[@]}"
      ;;
    tree)
      github_tree_plan "$owner" "$repo" "${segs[3]}" 4 "${segs[@]}"
      ;;
    issues)
      PLAN_ARGV=(gh issue view "${segs[3]}" --repo "$owner/$repo")
      ;;
    pull)
      PLAN_ARGV=(gh pr view "${segs[3]}" --repo "$owner/$repo")
      ;;
    discussions)
      PLAN_ARGV=(gh api "repos/$owner/$repo/discussions/${segs[3]}")
      ;;
    releases)
      if [ "${segs[3]}" = "tag" ] && [ "$n" -ge 5 ]; then
        PLAN_ARGV=(gh release view "${segs[4]}" --repo "$owner/$repo")
      else
        github_readme_plan "$owner" "$repo"
      fi
      ;;
    *)
      github_readme_plan "$owner" "$repo"
      ;;
  esac
}

# heading_of FILE — first markdown heading, used as the article title when the
# page has no usable <title>. Tabs are neutralised because the title lands in a
# TSV column. Prints an empty line when the file has no heading.
heading_of() {
  sed -n -e 's/^#\{1,6\}[[:space:]]\{1,\}//p' "$1" 2>/dev/null |
    head -1 |
    sed -e 's/[[:space:]]\{1,\}#\{1,\}[[:space:]]*$//' -e 's/[[:space:]]*$//' |
    tr '\t' ' '
}

# title_of URL KIND FILE — the note format requires a per-article title, so the
# manifest must supply one rather than leaving the reader to invent it. For HTML
# the real <title> is authoritative; ax caches parse-mode URLs for ~2min, so this
# second call hits the cache instead of refetching.
title_of() {
  local url="$1" kind="$2" file="$3" t=""
  if [ "$kind" = "html" ]; then
    t=$(ax "$url" title --text -m "$TIMEOUT" 2>/dev/null | head -1 | tr '\t' ' ')
  fi
  if [ -z "$t" ]; then t=$(heading_of "$file"); fi
  printf '%s' "$t"
}

# looks_like_pdf FILE — some hosts serve a PDF from an extensionless URL, so the
# suffix check in resolve_plan is only a hint; the magic bytes are the truth.
looks_like_pdf() {
  [ -s "$1" ] && [ "$(head -c 4 "$1" 2>/dev/null)" = "%PDF" ]
}

# fetch_one IDX URL OUTDIR — runs in a background job; appends one manifest row.
fetch_one() {
  local idx="$1" url="$2" outdir="$3"
  local out="$outdir/$idx.md"
  local err="$outdir/$idx.err"
  local status kind rc

  resolve_plan "$url"
  kind="$PLAN_KIND"

  if [ "$kind" = "pdf" ]; then
    out="$outdir/$idx.pdf"
    "${PLAN_ARGV[@]}" "$out" >"$err" 2>&1
    rc=$?
  elif [ "$PLAN_DECODE" -eq 1 ]; then
    "${PLAN_ARGV[@]}" 2>"$err" | base64 --decode >"$out" 2>>"$err"
    rc=${PIPESTATUS[0]}
  else
    "${PLAN_ARGV[@]}" >"$out" 2>"$err"
    rc=$?
  fi

  # An HTML request that came back as a PDF is re-fetched as a PDF, so the
  # caller reads it with Read --pages instead of staring at binary noise.
  if [ "$rc" -eq 0 ] && [ "$kind" = "html" ] && looks_like_pdf "$out"; then
    kind=pdf
    rm -f "$out"
    out="$outdir/$idx.pdf"
    ax "$url" -m "$TIMEOUT" -o "$out" >"$err" 2>&1
    rc=$?
  fi

  if [ "$rc" -ne 0 ]; then
    status=failed
  elif [ ! -s "$out" ]; then
    status=empty
  elif grep -q 'more result(s) hidden' "$err" 2>/dev/null; then
    # ax announces truncation on stderr. Surfacing it as its own status keeps a
    # half-read article from being summarized as if it were complete.
    status=partial
  else
    status=ok
    rm -f "$err"
  fi

  local title=""
  if [ "$status" = "ok" ] || [ "$status" = "partial" ]; then
    title=$(title_of "$url" "$kind" "$out")
  fi

  # One printf per job: writes under PIPE_BUF are atomic, so rows never interleave.
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$idx" "$kind" "$status" "$title" "$out" "$url" \
    >>"$outdir/manifest.part"
}

main() {
  local urlfile=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -o) OUTDIR="$2"; shift 2 ;;
      -b) BUDGET="$2"; shift 2 ;;
      -j) JOBS="$2"; shift 2 ;;
      --plan)
        resolve_plan "$2"
        printf '%s\t%s\n' "$PLAN_KIND" "${PLAN_ARGV[*]}"
        return 0
        ;;
      --heading)
        heading_of "$2"
        return 0
        ;;
      --github-dir)
        github_dir_fetch "$2" "$3" "$4" "$5"
        return $?
        ;;
      --dir-render)
        dir_render "$2" "$3"
        return $?
        ;;
      --dir-doc)
        dir_doc "$2"
        return $?
        ;;
      -h | --help) sed -n '2,30p' "$0"; return 0 ;;
      *) urlfile="$1"; shift ;;
    esac
  done

  # An unreadable URL file must not degrade into an empty manifest: that looks
  # exactly like "every URL failed" to the caller. $TMPDIR differs inside and
  # outside the sandbox, so a stale relative path is an easy mistake to make.
  if [ -n "$urlfile" ] && [ ! -r "$urlfile" ]; then
    printf 'fetch-batch.sh: cannot read URL file: %s\n' "$urlfile" >&2
    return 2
  fi

  if [ -z "$OUTDIR" ]; then
    OUTDIR="$(mktemp -d "${TMPDIR:-/tmp}/inbox-fetch.XXXXXX")"
  fi
  mkdir -p "$OUTDIR"
  : >"$OUTDIR/manifest.part"

  local urls=()
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "" | \#*) continue ;;
    esac
    urls[${#urls[@]}]="$line"
  done < <(if [ -n "$urlfile" ]; then cat "$urlfile"; else cat; fi)

  local i idx
  for ((i = 0; i < ${#urls[@]}; i++)); do
    while [ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$JOBS" ]; do
      sleep 0.2
    done
    idx=$(printf '%03d' "$((i + 1))")
    fetch_one "$idx" "${urls[$i]}" "$OUTDIR" &
  done
  wait

  {
    printf 'idx\tkind\tstatus\ttitle\tpath\turl\n'
    sort "$OUTDIR/manifest.part"
  } >"$OUTDIR/manifest.tsv"
  rm -f "$OUTDIR/manifest.part"

  cat "$OUTDIR/manifest.tsv"
  printf '\nmanifest: %s\n' "$OUTDIR/manifest.tsv"
}

main "$@"
