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
# The Claude Desktop config switched from symlink to jq-merge management in install.sh.
# We only inject mcpServers, and it is an app-owned file, so we do not auto-revert here
# (manually remove mcpServers.inkdrop or restore from .bak.<timestamp>).
echo "  note    : claude_desktop_config.json is merge-managed (revert manually)"
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
