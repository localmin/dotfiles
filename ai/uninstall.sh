#!/usr/bin/env bash
# uninstall.sh — Remove symlinks created by install.sh and restore backups.

set -euo pipefail

AI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── helpers ───────────────────────────────────────────────────────────────────

unlink_restore() {
  local dst="$1"
  if [[ -L "$dst" ]]; then
    rm "$dst"
    echo "  removed : $dst"
    if [[ -e "$dst.bak" ]]; then
      mv "$dst.bak" "$dst"
      echo "  restored: $dst.bak → $dst"
    fi
  else
    echo "  skip    : $dst (not a symlink)"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

echo "=== ai/uninstall.sh ==="

unlink_restore "$HOME/CLAUDE.md"
# Claude Desktop の config は install.sh で symlink でなく jq マージ管理に変更済み。
# mcpServers だけを差し込んでおりアプリ所有ファイルのため、ここでは自動 revert しない
# (手動で mcpServers.inkdrop を消すか .bak.<timestamp> から戻す)。
echo "  note    : claude_desktop_config.json は merge 管理 (revert は手動)"
unlink_restore "$HOME/.gemini/antigravity-cli/settings.json"
unlink_restore "$HOME/.codex/config.toml"

for skill_dir in "$AI_DIR/skills"/*/; do
  [[ -d "$skill_dir" ]] || continue
  skill_name="$(basename "$skill_dir")"
  unlink_restore "$HOME/.claude/skills/$skill_name"
  unlink_restore "$HOME/.gemini/skills/$skill_name"
  unlink_restore "$HOME/.codex/skills/$skill_name"
done

claude mcp remove inkdrop -s user 2>/dev/null && echo "  removed : mcp inkdrop (user scope)" || echo "  skip    : mcp inkdrop (not registered)"

echo ""
echo "=== done ==="
