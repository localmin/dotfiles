#!/usr/bin/env bash
# install.sh — AI tools setup (information pipeline)
# Creates symlinks to activate CLAUDE.md, MCP configs, and Skills.

set -euo pipefail

AI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── helpers ───────────────────────────────────────────────────────────────────

# Claude Code CLI の user スコープに MCP サーバーを登録する(冪等)
mcp_add() {
  local name="$1" cmd="$2"; shift 2
  claude mcp remove "$name" -s user 2>/dev/null || true
  claude mcp add -s user -- "$name" "$cmd" "$@"
  echo "  mcp    : $name → $cmd $*"
}

# SKILL.md に YAML frontmatter (name + description) があるか検証
validate_skill() {
  local skill_md="$1"
  [[ -f "$skill_md" ]] || { echo "  ERROR  : $skill_md not found" >&2; return 1; }
  # 1行目が `---` で始まり、name と description フィールドが含まれることを確認
  if ! head -n 1 "$skill_md" | grep -q '^---$'; then
    echo "  ERROR  : $skill_md missing YAML frontmatter (---)" >&2
    return 1
  fi
  if ! awk '/^---$/{c++; if(c==2) exit} c==1 && /^name:/{n=1} c==1 && /^description:/{d=1} END{exit !(n && d)}' "$skill_md"; then
    echo "  ERROR  : $skill_md frontmatter missing name or description" >&2
    return 1
  fi
}

link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"

  if [[ -e "$dst" && ! -L "$dst" ]]; then
    echo "  backup : $dst → $dst.bak"
    mv "$dst" "$dst.bak"
  fi

  if [[ -L "$dst" ]]; then
    if [[ "$(readlink "$dst")" == "$src" ]]; then
      echo "  skip   : $dst (already linked)"
      return
    fi
    echo "  relink : $dst"
    rm "$dst"
  fi

  ln -s "$src" "$dst"
  echo "  linked : $dst"
  echo "        -> $src"
}

# ファイルに内容がある場合のみリンク(空のプレースホルダーをリンクしない)
link_if_nonempty() {
  local src="$1" dst="$2"
  if [[ ! -s "$src" ]]; then
    echo "  skip   : $(basename "$src") (empty, not yet configured)"
    return
  fi
  link "$src" "$dst"
}

# ── main ──────────────────────────────────────────────────────────────────────

echo "=== ai/install.sh ==="

# 1. Global CLAUDE.md (read by Claude Code, Antigravity CLI, Codex CLI)
link "$AI_DIR/CLAUDE.md" "$HOME/CLAUDE.md"

# 2. Claude Desktop app — MCP config を jq マージ
# このファイルは Claude Desktop アプリ自身が preferences 等を書き込む「アプリ所有」ファイル。
# symlink するとアプリが実ファイルへ戻す/アプリの状態を repo へ漏らすため、symlink せず
# dotfiles が管理したい mcpServers だけを既存ファイルへマージする(他キーは保全・冪等)。
desktop_cfg="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
mcp_fragment="$AI_DIR/claude/claude_desktop_mcp.json"
if command -v jq >/dev/null 2>&1; then
  mkdir -p "$(dirname "$desktop_cfg")"
  [[ -f "$desktop_cfg" ]] || echo '{}' > "$desktop_cfg"
  merged="$(mktemp)"
  if jq -s '.[0] * .[1]' "$desktop_cfg" "$mcp_fragment" > "$merged" 2>/dev/null; then
    if cmp -s "$merged" "$desktop_cfg"; then
      rm -f "$merged"; echo "  skip   : claude_desktop_config.json (mcpServers already current)"
    else
      cp "$desktop_cfg" "$desktop_cfg.bak.$(date +%Y%m%d%H%M%S)"
      mv "$merged" "$desktop_cfg"
      echo "  merged : claude_desktop_config.json (mcpServers) — 既存は .bak.<timestamp> に退避"
    fi
  else
    rm -f "$merged"; echo "  warn   : claude_desktop_config.json のマージ失敗 (未変更のまま)"
  fi
else
  echo "  warn   : jq not found; Claude Desktop の MCP マージをスキップ"
fi

# 3. Antigravity CLI — context + MCP config (設定が書かれたら有効になる)
link_if_nonempty "$AI_DIR/antigravity/settings.json" "$HOME/.gemini/antigravity-cli/settings.json"

# 4. Codex CLI — fallback filenames + MCP config (設定が書かれたら有効になる)
link_if_nonempty "$AI_DIR/codex/config.toml" "$HOME/.codex/config.toml"

# 5. Skills → ~/.claude/skills/ + ~/.gemini/skills/ + ~/.codex/skills/ (全 CLI で auto-discovery)
# 外部 vendored skill (ai/vendor/manifest.tsv) を欠けていれば pinned commit から取得
if [[ -x "$AI_DIR/vendor/fetch.sh" ]]; then
  "$AI_DIR/vendor/fetch.sh" --if-missing || echo "  warn   : vendor fetch failed; vendored skills skipped"
fi
mkdir -p "$HOME/.claude/skills" "$HOME/.gemini/skills" "$HOME/.codex/skills"
for skill_dir in "$AI_DIR/skills"/*/; do
  [[ -d "$skill_dir" ]] || continue
  skill_name="$(basename "$skill_dir")"
  validate_skill "$skill_dir/SKILL.md" || { echo "  abort  : $skill_name (frontmatter invalid)"; exit 1; }
  link "$skill_dir" "$HOME/.claude/skills/$skill_name"
  link "$skill_dir" "$HOME/.gemini/skills/$skill_name"
  link "$skill_dir" "$HOME/.codex/skills/$skill_name"
done

# 6. Claude Code CLI — Inkdrop MCP は user スコープに登録しない
# 代わりに ~/dotfiles/.mcp.json をプロジェクトスコープで読ませる
# (Claude を ~/dotfiles から起動した時のみ inkdrop が有効化される)
# 既存の user スコープ登録があれば削除する(冪等)
claude mcp remove inkdrop -s user 2>/dev/null || true

# 7. Language servers for enabled LSP plugins (typescript-lsp / pyright-lsp / ruby-lsp / clangd-lsp)
#    Plugins only enable Claude Code's built-in LSP; the server binaries are required per machine.
if command -v npm >/dev/null 2>&1; then
  npm install -g typescript-language-server typescript pyright >/dev/null 2>&1 \
    && echo "  ok     : npm LSP servers (typescript-language-server, typescript, pyright)" \
    || echo "  warn   : npm LSP install failed"
else
  echo "  warn   : npm not found; skip typescript/pyright LSP servers"
fi
# ruby-lsp requires ruby >= 3.0 (macOS bundled 2.6 cannot build prism)
if command -v gem >/dev/null 2>&1 && ruby -e 'exit(RUBY_VERSION.to_f >= 3.0 ? 0 : 1)' 2>/dev/null; then
  gem install ruby-lsp >/dev/null 2>&1 && echo "  ok     : ruby-lsp gem" || echo "  warn   : ruby-lsp gem install failed"
else
  echo "  skip   : ruby-lsp (needs ruby >= 3.0; current $(ruby -v 2>/dev/null | awk '{print $2}'))"
fi
# clangd: bundled with Xcode CLT on macOS (/usr/bin/clangd); 'apt install clangd' on Linux
command -v clangd >/dev/null 2>&1 \
  && echo "  ok     : clangd present ($(command -v clangd))" \
  || echo "  warn   : clangd missing (mac: xcode-select --install / linux: apt install clangd)"

echo ""
echo "=== done ==="
