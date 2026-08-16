# dotfiles — 情報収集パイプライン

ブラウザで読んだ情報を Inkdrop に集約し、日次/週次/月次/年次でレビューするパイプライン。各機能は `coding-agents/skills/<name>/SKILL.md` に skill として実装され、`coding-agents/install.sh` で Claude / Antigravity / Codex の各 CLI へ symlink 配布される。

## リポジトリ構成

- `coding-agents/` — 全 CLI 共有の設定。グローバル CLAUDE.md（`~/CLAUDE.md` の実体）・skills・vendor 機構・各 CLI 向け config
- `.claude/` — Claude Code の settings / hooks（`dotfilesLink.sh` で `~/.claude/` へリンク）
- `dotfilesLink.sh` / `coding-agents/install.sh` — symlink・環境再現スクリプト
- 運用: master 直コミット / 直 push（PR なし）

## Inkdrop MCP（接続情報）

接続: `localhost:19840`（`@inkdropapp/mcp-server` 経由。この repo の `.mcp.json` が project スコープで提供し、認証は 1Password `op run --env-file=coding-agents/inkdrop.op.env`）

検索修飾子: `book:` / `tag:` / `status:` / `title:`

ノート status: `active`（通常）/ `completed`（アーカイブ用）/ `dropped` / `none`
