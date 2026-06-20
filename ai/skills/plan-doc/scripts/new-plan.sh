#!/usr/bin/env bash
# new-plan.sh — plan doc 雛形を <project-root>/.claude/plans/ に生成し INDEX.md へ登録する。
# usage: new-plan.sh <slug> [<project-root>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../template.md"

slug="${1:-}"
if [[ -z "$slug" ]]; then
  echo "usage: new-plan.sh <slug> [<project-root>]" >&2
  exit 1
fi
# slug を安全化（英数・ハイフン・アンダースコアのみ）
slug="$(printf '%s' "$slug" | tr ' ' '-' | tr -cd 'A-Za-z0-9._-')"
[[ -n "$slug" ]] || { echo "ERROR: slug が空です" >&2; exit 1; }

# project-root: 引数 > git トップ > カレント
if [[ -n "${2:-}" ]]; then
  root="$2"
elif root_git="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  root="$root_git"
else
  root="$PWD"
fi
root="$(cd "$root" && pwd)"

[[ -f "$TEMPLATE" ]] || { echo "ERROR: template が見つかりません: $TEMPLATE" >&2; exit 1; }

date_str="$(date +%Y-%m-%d)"
plans_dir="$root/.claude/plans"
doc="$plans_dir/${date_str}-${slug}.md"
index="$plans_dir/INDEX.md"

mkdir -p "$plans_dir"

if [[ -e "$doc" ]]; then
  echo "skip   : 既に存在します → $doc"
else
  sed -e "s/{{TITLE}}/${slug}/g" \
      -e "s/{{DATE}}/${date_str}/g" \
      -e "s/{{SLUG}}/${slug}/g" \
      "$TEMPLATE" > "$doc"
  echo "created: $doc"
fi

# INDEX.md を upsert
if [[ ! -f "$index" ]]; then
  printf '# Plans Index\n\n進行中・過去の設計 doc 索引。再開時はまずここを読み、関連エントリだけ詳細を開く。\n\n' > "$index"
  echo "created: $index"
fi

rel="${date_str}-${slug}.md"
line="- [${date_str}-${slug}](${rel}) — （フックを記入）"
if grep -qF "(${rel})" "$index"; then
  echo "skip   : INDEX に登録済み → $rel"
else
  printf '%s\n' "$line" >> "$index"
  echo "indexed: $rel"
fi

echo
echo "次: $doc の各見出し（Goals/Spec/Task分割/実装の進め方/動作確認）を埋め、INDEX のフックを書き換えてください。"
