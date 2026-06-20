---
name: notebooklm-judge
description: Inkdropのタグ別ノート数と追加頻度を集計し、NotebookLMへのトピック昇格判定（推奨/様子見/不要）を出力する。タグ名指定または全タグ走査。
---

# notebooklm-judge

指定タグのノートを集計し、NotebookLM へのトピック昇格を判定する。

## Inkdrop MCP の使用方法と注意点

スキル開始前に、各CLIにおける Inkdrop MCP の呼び出し方針を確認すること。
特に 1Password (`op run`) による認証が走るため、不要なタイミングでの認証ポップアップを防ぐ必要がある。

- **Claude Code**: `~/dotfiles/` から `claude` を起動する（`~/dotfiles/.mcp.json` で自動読み込み）
- **Codex**: `~/dotfiles/ai/codex/config.toml` の `enabled = false` を削除
- **Antigravity**:
  Antigravity CLI では `antigravity mcp enable inkdrop` による常時有効化は行わないこと（関係ない操作でも 1Password が立ち上がるのを防ぐため）。
  代わりに、一時的なスクリプト等を生成し、以下のように `run_shell_command` 経由で MCP サーバーの stdio に直接 JSON-RPC を流し込んで単発実行（Stateless Invocation）すること。
  例: `echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search-notes","arguments":{"keyword":"tag:vibe-coding"}}}' | op run --env-file=~/dotfiles/ai/inkdrop.op.env -- npx --prefer-offline -y @inkdropapp/mcp-server`

Stateless Invocation は1回あたり起動コスト（認証 + npm 解決）が大きいため、**MCP 呼び出し回数の最小化** と **並列化可能な呼び出しの同時実行** で起動コストを隠すこと。特に「タグ未指定で全タグ走査」は並列化必須。

## 入力

タグ名（例: `vibe-coding`）。複数指定可。省略時は全タグを対象に候補を探す。

## 昇格基準

各ノートの `createdAt` を月単位に集計して判定する。

| 判定 | 条件 |
|---|---|
| **昇格推奨** | 本数 3本以上 **かつ** 直近3ヶ月のうち2ヶ月以上に分散して追加されている |
| **様子見** | 本数 3本以上だが直近3ヶ月で1ヶ月のみに集中（単月集中型）／本数 2本だが2ヶ月以上に分散（本数不足型） |
| **不要** | 本数 1本以下、または本数 2本以下で単月集中 |

「様子見」は再判定までの目安を出力に含める:
- **本数不足型** (本数 2本): 「あと 1 本」
- **単月集中型** (本数 3本以上だが単月): 「あと 1 ヶ月」

## 手順

1. **対象タグのノートを取得**: `search-notes(keyword: 'tag:<タグ名>')` で全件取得
2. **集計**: 本数・最古日・最新日・月別本数（直近3ヶ月）を算出
3. **判定**: 上記「昇格基準」と照合して以下のいずれかを出力:
   - **昇格推奨** — NotebookLM に新規トピックを作成する
   - **様子見** — 「あと N 本」または「あと N ヶ月」を併記
   - **不要** — 本数・継続性ともに基準未満
4. **タグ未指定の場合**:
   - `list-tags` でタグ一覧を取得（MCP 1回）
   - 各タグに対する `search-notes(keyword: 'tag:<タグ名>')` を **すべて並列で** 実行する。直列だとタグ数 × 起動コストでかなり遅くなるため、Antigravity Stateless でも並列化必須。
   - 集計結果から昇格推奨・様子見の候補一覧を表示

## 出力例

```
タグ: vibe-coding
  本数: 7本（2026-03 〜 2026-05）
  月別: 3月 2本 / 4月 3本 / 5月 2本
  判定: 昇格推奨 ✓

タグ: prompt-caching
  本数: 2本（2026-05）
  判定: 様子見（あと1本 or 1ヶ月）
```

## NotebookLM での操作（判定後）

昇格推奨の場合、ユーザーが手動で NotebookLM に追加する:
1. NotebookLM で新規ノートブックを作成（タグ名をそのままトピック名に）
2. Inkdrop から該当ノートをエクスポート or URL共有で追加
3. 「既存ノートブックとの差分」をチャットで確認

## タイムアウトとリトライ方針

- **MCP 呼び出し (Stateless = Antigravity)**: タイムアウト 60秒（`op run` 認証 + `npx` 起動を含む）。失敗時は1回だけリトライしてよい
- **MCP 呼び出し (Persistent = Claude / Codex)**: タイムアウト 30秒。失敗時は1回だけリトライしてよい

## 注意

- NotebookLM への追加はこのスキルでは行わない（手動操作）
- 昇格後もInkdropのノートはそのまま残す（削除しない）
