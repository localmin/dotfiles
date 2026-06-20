---
name: monthly-summary
description: 当月にInkdrop inboxから昇格したノートを集計してテンプレートに沿って月次サマリーを作成し、monthlyノートブックに保存する。NotebookLM昇格候補も提示。月次運用想定。
---

# monthly-summary

当月に inbox から昇格したノートを集計し、月次サマリーを Inkdrop に作成する。

## Inkdrop MCP の使用方法と注意点

スキル開始前に、各CLIにおける Inkdrop MCP の呼び出し方針を確認すること。
特に 1Password (`op run`) による認証が走るため、不要なタイミングでの認証ポップアップを防ぐ必要がある。

- **Claude Code**: `~/dotfiles/` から `claude` を起動する（`~/dotfiles/.mcp.json` で自動読み込み）
- **Codex**: `~/dotfiles/ai/codex/config.toml` の `enabled = false` を削除
- **Antigravity**:
  Antigravity CLI では `antigravity mcp enable inkdrop` による常時有効化は行わないこと（関係ない操作でも 1Password が立ち上がるのを防ぐため）。
  代わりに、一時的なスクリプト等を生成し、以下のように `run_shell_command` 経由で MCP サーバーの stdio に直接 JSON-RPC を流し込んで単発実行（Stateless Invocation）すること。
  例: `echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search-notes","arguments":{"keyword":"book:tech/AI"}}}' | op run --env-file=~/dotfiles/ai/inkdrop.op.env -- npx --prefer-offline -y @inkdropapp/mcp-server`

Stateless Invocation は1回あたり起動コスト（認証 + npm 解決）が大きいため、**MCP 呼び出し回数の最小化** と **並列化可能な呼び出しの同時実行** で起動コストを隠すこと。

## 入力

対象月（例: `2026-05`）。省略時は前月。

## 集計対象ノートブック

```
tech/web-engineering / tech/AI / tech/infra / tech/cryptography
tech/low-layer / tech/neovim / others/ / someday-ideas/
```

(`inbox/` `monthly/` `yearly/` `weekly/` は集計対象外)

## 手順

Inkdrop の検索修飾子に **日付フィルタは存在しない**（`book:` / `tag:` / `status:` / `title:` のみ）ため、当月分への絞り込みはノートの `createdAt` / `updatedAt` をローカルでフィルタする必要がある。MCP 呼び出しはノートブック単位で並列化してコストを隠す。

1. **昇格ノートを収集**:
   - 集計対象ノートブックごとに `search-notes(keyword: 'book:<bookId>')` を **すべて並列で** 実行する（直列だと N 倍の起動コストがかかる）。
   - 加えて `search-notes(keyword: 'status:completed')` を 1 本（当月アーカイブされた個別ノート用）。
   - 取得したノートを `createdAt` / `updatedAt` で当月分にローカルフィルタする。
2. **タグ別に集計**: どのテーマに何本昇格したか整理
3. **月次サマリーを下書き**: 以下のテンプレートに沿って生成

```markdown
# YYYY-MM 月次サマリー

## 今月学んだこと

1. 
2. 
3. 

## 気になったテーマ

- 

## 来月深掘りしたいこと

- 

## 昇格ノート一覧

| タグ | 本数 | 代表的なノート |
|---|---|---|
| tag-name | N | [タイトル](inkdrop://note/xxx) |

## NotebookLM 昇格候補

- タグ `xxx`: N本（基準: 3本以上）
```

4. **ノートを作成**: `create-note` でタイトル `YYYY-MM 月次サマリー`、`bookId: monthly`、`status: active`
5. **NotebookLM 候補の提示**: 3本以上のタグがあれば `notebooklm-judge` の実行を提案

## タイムアウトとリトライ方針

- **MCP 呼び出し (Stateless = Antigravity)**: タイムアウト 60秒（`op run` 認証 + `npx` 起動を含む）。失敗時は1回だけリトライしてよい
- **MCP 呼び出し (Persistent = Claude / Codex)**: タイムアウト 30秒。失敗時は1回だけリトライしてよい

## 注意

- 下書きはあくまで叩き台。「学んだこと」「来月の関心」はユーザーが加筆する
- 昇格ノートの一覧は網羅より代表的なものを数件に絞る
