#!/usr/bin/env bash
# new-plan.sh — generate a plan-doc template under <project-root>/.claude/plans/ and register it in INDEX.md.
# usage: new-plan.sh <slug> [<project-root>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../template.md"

slug="${1:-}"
if [[ -z "$slug" ]]; then
  echo "usage: new-plan.sh <slug> [<project-root>]" >&2
  exit 1
fi
# Sanitize the slug (alphanumerics, hyphen, underscore only)
slug="$(printf '%s' "$slug" | tr ' ' '-' | tr -cd 'A-Za-z0-9._-')"
[[ -n "$slug" ]] || { echo "ERROR: slug is empty" >&2; exit 1; }

# project-root: argument > git top-level > current directory
if [[ -n "${2:-}" ]]; then
  root="$2"
elif root_git="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  root="$root_git"
else
  root="$PWD"
fi
root="$(cd "$root" && pwd)"

[[ -f "$TEMPLATE" ]] || { echo "ERROR: template not found: $TEMPLATE" >&2; exit 1; }

date_str="$(date +%Y-%m-%d)"
plans_dir="$root/.claude/plans"
doc="$plans_dir/${date_str}-${slug}.md"
index="$plans_dir/INDEX.md"

mkdir -p "$plans_dir"

if [[ -e "$doc" ]]; then
  echo "skip   : already exists → $doc"
else
  sed -e "s/{{TITLE}}/${slug}/g" \
      -e "s/{{DATE}}/${date_str}/g" \
      -e "s/{{SLUG}}/${slug}/g" \
      "$TEMPLATE" > "$doc"
  echo "created: $doc"
fi

# Upsert INDEX.md
if [[ ! -f "$index" ]]; then
  printf '# Plans Index\n\n進行中・過去の設計 doc 索引。再開時はまずここを読み、関連エントリだけ詳細を開く。\n\n' > "$index"
  echo "created: $index"
fi

rel="${date_str}-${slug}.md"
line="- [${date_str}-${slug}](${rel}) — （フックを記入）"
if grep -qF "(${rel})" "$index"; then
  echo "skip   : already in INDEX → $rel"
else
  printf '%s\n' "$line" >> "$index"
  echo "indexed: $rel"
fi

echo
echo "次: $doc の各見出し（Goals/Spec/Task分割/実装の進め方/動作確認）を埋め、INDEX のフックを書き換えてください。"
