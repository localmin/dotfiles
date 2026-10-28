---
name: monthly-summary
description: 対象月（既定は前月）にInkdrop inboxから昇格したノート（weekly-review で「育てる」判定されたもの）を集計してテンプレートに沿って月次サマリーを作成し、monthlyノートブックに保存する。NotebookLM昇格候補も提示。「月次サマリー」「今月のまとめ」を頼まれたら使う。月次運用想定。
---

# monthly-summary

対象月に inbox から昇格したノートを集計し、月次サマリーを Inkdrop に作成する。

## Inkdrop MCP の使用方法と注意点

スキル開始前に、各CLIにおける Inkdrop MCP の呼び出し方針を確認すること。
特に 1Password (`op run`) による認証が走るため、不要なタイミングでの認証ポップアップを防ぐ必要がある。

- **Claude Code**: `~/dotfiles/` から `claude` を起動する（`~/dotfiles/.mcp.json` で自動読み込み）
- **Codex**: `~/dotfiles/coding-agents/codex/config.toml` の `enabled = false` を削除
- **Antigravity**:
  Antigravity CLI では `antigravity mcp enable inkdrop` による常時有効化は行わないこと（関係ない操作でも 1Password が立ち上がるのを防ぐため）。
  代わりに、一時的なスクリプト等を生成し、以下のように `run_shell_command` 経由で MCP サーバーの stdio に直接 JSON-RPC を流し込んで単発実行（Stateless Invocation）すること。
  例: `echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search-notes","arguments":{"keyword":"book:tech/AI"}}}' | op run --env-file=~/dotfiles/coding-agents/inkdrop.op.env -- npx --prefer-offline -y @inkdropapp/mcp-server`

Stateless Invocation は1回あたり起動コスト（認証 + npm 解決）が大きいため、**MCP 呼び出し回数の最小化** と **並列化可能な呼び出しの同時実行** で起動コストを隠すこと。

## 入力

対象月（例: `2026-05`）。省略時は前月。

## 「昇格」の定義

**昇格ノート = inbox 日次ノートの `- 週次判定: 育てる → [タイトル](inkdrop://note/<id>)` 行が指すノートのうち、`createdAt` が対象月のもの**（weekly-review が「育てる」で個別ノートを作った時点＝昇格時点）。ノートブックの全ノートを日付で拾う方式は使わない（古いノートを編集しただけのものや、inbox を経由しない手書きノートが混ざる）。

## ノートブックの実 ID

`search-notes` の `book:` 修飾子は**表示名**で引く（`book:inbox`）。`create-note` の `bookId` には**実 ID** が要る。2026-09-21 時点の実 ID（昇格先になりうるもの）:

```
book:_dtsK1wL    tech/web-engineering
book:TnFNXDOy    tech/AI
book:7beOT60T    tech/infra
book:Q3uI87J9    tech/cryptography
book:SvJkLqvg    tech/low-layer
book:5uqtSYb-    tech/neovim
book:YPhSGe-q    others
book:GkmAPwUu    someday-ideas
```

保存先の `monthly` は `book:rFt2TWxB`。`inbox` は `book:51GBqxKj`（`yearly` / `weekly` は未作成）。

ID が合わないときは `list-notebooks` で引き直し、この一覧を更新する。

## 手順

Inkdrop の検索修飾子に **日付フィルタは存在しない**（`book:` / `tag:` / `status:` / `title:` のみ）。MCP 呼び出しは並列化してコストを隠す。

1. **昇格ノートを収集**:
   - 対象月と前月の inbox 日次ノートを `search-notes(keyword: 'book:inbox title:"inbox YYYY-MM"')` × 2 で **並列に** 引く（前月も見るのは、前月末に取り込んだ記事が対象月の weekly-review で育てられることがあるため）。**status で絞らない**（目を通した日次ノートは `completed` になっている）。
   - 日次ノートの本文は **MCP の `read-note` で直接読まない**（1 本 60,000 字超になりうる）。inbox-capture の `~/dotfiles/coding-agents/skills/inbox-capture/scripts/note-head.sh -o <ノートごとの出力先> <note:ID>` を **並列で** 実行して `body.md` に落とし（1Password が走るため sandbox 外）、`grep -o 'inkdrop://note/[^)]*'` を `週次判定: 育てる` 行に対してだけ当ててリンク先 ID を集める。
   - リンク先（個別ノート。小さい）を `read-note` で **並列に** 読み、`createdAt` が対象月のものだけ残す。同じ ID は 1 本に数える。
2. **タグ別に集計**: どのテーマに何本昇格したか整理する。`read-note` の `tags` は tag ID なので、タグ名は `list-tags` で ID から引く。
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

- タグ `xxx`: 今月 N本（判定は notebooklm-judge）
```

4. **ノートを作成**: `create-note` でタイトル `YYYY-MM 月次サマリー`、`bookId: "book:rFt2TWxB"`（monthly）、`status: "active"`
5. **NotebookLM 候補の提示**: 今月昇格のあったタグを候補として挙げ、`notebooklm-judge` の実行を提案する（推奨/様子見/不要の判定基準は notebooklm-judge 側が正。ここで本数の閾値を独自に持たない）

## タイムアウトとリトライ方針

- **MCP 呼び出し (Stateless = Antigravity)**: タイムアウト 60秒（`op run` 認証 + `npx` 起動を含む）。失敗時は1回だけリトライしてよい
- **MCP 呼び出し (Persistent = Claude / Codex)**: タイムアウト 30秒。失敗時は1回だけリトライしてよい

## 注意

- 下書きはあくまで叩き台。「学んだこと」「来月の関心」はユーザーが加筆する
- 昇格ノートの一覧は網羅より代表的なものを数件に絞る
