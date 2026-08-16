#!/usr/bin/env bash
# PreToolUse hook (Claude Code), matcher: WebFetch.
# Enforce the "use gh for GitHub" rule deterministically: block WebFetch to
# github.com content hosts and point at the equivalent gh command. Non-GitHub
# hosts, docs.github.com, and *.github.io are left alone (gh cannot fetch them).
set -uo pipefail

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[[ "$tool" == "WebFetch" ]] || exit 0

url="$(printf '%s' "$input" | jq -r '.tool_input.url // empty' 2>/dev/null || true)"
[[ -n "$url" ]] || exit 0

# Extract host (strip scheme, then path/query).
host="${url#*://}"; host="${host%%/*}"; host="${host%%:*}"
host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"

case "$host" in
  github.com|gist.github.com|raw.githubusercontent.com|api.github.com) ;;
  *) exit 0 ;;   # not a gh-servable GitHub host (docs.github.com, *.github.io, others)
esac

# Derive owner/repo and a suggested gh command from the URL shape.
path="${url#*://*/}"                       # everything after host
suggest="gh api <endpoint>   # or: gh repo view <owner>/<repo>"
case "$url" in
  *gist.github.com/*)
    gid="${url##*/}"; suggest="gh gist view ${gid}" ;;
  *raw.githubusercontent.com/*)
    suggest="gh api repos/<owner>/<repo>/contents/<path>   # raw blob" ;;
  *api.github.com/*)
    suggest="gh api ${path}" ;;
  */pull/*)
    owner_repo="${path%%/pull/*}"; n="${path#*/pull/}"; n="${n%%/*}"
    suggest="gh pr view ${n} --repo ${owner_repo} --comments" ;;
  */issues/*)
    owner_repo="${path%%/issues/*}"; n="${path#*/issues/}"; n="${n%%/*}"
    suggest="gh issue view ${n} --repo ${owner_repo} --comments" ;;
  */releases*)
    owner_repo="${path%%/releases*}"
    suggest="gh release view --repo ${owner_repo}" ;;
  */blob/*)
    owner_repo="${path%%/blob/*}"; rest="${path#*/blob/}"; ref="${rest%%/*}"; fp="${rest#*/}"
    suggest="gh api repos/${owner_repo}/contents/${fp}?ref=${ref} --jq .content   # base64" ;;
  */tree/*)
    owner_repo="${path%%/tree/*}"
    suggest="gh api repos/${owner_repo}/contents/<path>" ;;
  *)
    owner_repo="${path%%/*}/"; owner_repo+="$(x="${path#*/}"; printf '%s' "${x%%/*}")"
    suggest="gh repo view ${owner_repo}   # or: gh api repos/${owner_repo}" ;;
esac

cat >&2 <<EOF
WebFetch to a GitHub host is blocked — use gh instead (CLAUDE.md: "GitHub 参照は gh 優先").
  URL: ${url}
  Try: ${suggest}

If gh truly cannot retrieve this content, explain why to the user before considering alternatives.
EOF
exit 2
