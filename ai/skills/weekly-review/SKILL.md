---
name: weekly-review
description: Inkdropのinbox日次まとめから「後で読む」マークの記事を抽出し、育てる/捨てるの2択で整理する。育てる場合は個別ノート化してテーマ別ノートブックへ移動。NotebookLM昇格候補も提示。週次運用想定。
---

# weekly-review

inbox の日次まとめノートから **「後で読む」** とマークされた記事だけを抽出し、深読みして整理する。

## Inkdrop MCP の使用方法と注意点

スキル開始前に、各CLIにおける Inkdrop MCP の呼び出し方針を確認すること。
特に 1Password (`op run`) による認証が走るため、不要なタイミングでの認証ポップアップを防ぐ必要がある。

- **Claude Code**: `~/dotfiles/` から `claude` を起動する（`~/dotfiles/.mcp.json` で自動読み込み）
- **Codex**: `~/dotfiles/ai/codex/config.toml` の `enabled = false` を削除
- **Antigravity**:
  Antigravity CLI では `antigravity mcp enable inkdrop` による常時有効化は行わないこと（関係ない操作でも 1Password が立ち上がるのを防ぐため）。
  代わりに、一時的なスクリプト等を生成し、以下のように `run_shell_command` 経由で MCP サーバーの stdio に直接 JSON-RPC を流し込んで単発実行（Stateless Invocation）すること。
  例: `echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search-notes","arguments":{"keyword":"book:inbox"}}}' | op run --env-file=~/dotfiles/ai/inkdrop.op.env -- npx --prefer-offline -y @inkdropapp/mcp-server`

Stateless Invocation は1回あたり起動コスト（認証 + npm 解決）が大きいため、**MCP 呼び出し回数の最小化** と **並列化可能な呼び出しの同時実行** で起動コストを隠すこと。

## 入力

対象期間（必須）。例: `2026-04-28 〜 2026-05-04`

起動時にユーザーが指定する。指定がない場合は必ず確認してから進むこと。

## 前提

inbox-capture 時点で記事には3つの読了判定が付いている:

| 読了判定 | 日次の扱い | 週次の扱い |
|---|---|---|
| 即読了 | その場で読了済み | **対象外**（日次まとめに残すだけ） |
| 要約で十分 | 要約で完了 | **対象外**（日次まとめに残すだけ） |
| 後で読む | 深読み待ち | **本スキルの対象** |

「即読了」「要約で十分」のセクションは日次まとめノートに残ったままになる(検索で発掘可能)。古い日次まとめノート自体は月次/年次レビューで整理する。

## 移動先ノートブック（育てる場合の bookId）

```
tech/web-engineering    # ソフトウェア工学・ウェブ技術全般
tech/AI                 # AI開発手法・vibe-coding・harness-engineering
tech/infra              # ネットワーク・DC・GPUクラスタ
tech/cryptography       # 暗号
tech/low-layer          # OS・ドライバ・コンパイラ・仮想化
tech/neovim             # Neovim 関連
others/                 # その他
someday-ideas/          # 長期構想・未分解の興味
```

## 手順

Stateless MCP の起動コストを抑えるため、検索の絞り込みと並列 read-note を活用する。

1. **対象ノートを検索（絞り込み）**:
   - `list-notes(bookId: inbox)` で全件取得は禁止（inbox 肥大化時に重い）。必ず `search-notes` の `title:` 修飾子で月単位に絞る。
   - 期間が同月内なら 1 回、月をまたぐなら **月ごとに並列で** 実行する。
     - 同月内: `search-notes(keyword: 'book:inbox title:"inbox YYYY-MM"')`
     - 月またぎ (例: 2026-04-28 〜 2026-05-04): `book:inbox title:"inbox 2026-04"` と `book:inbox title:"inbox 2026-05"` を並列に呼び、結果をマージ
   - 取得後、タイトルの日付を解析して指定期間内のノートだけに絞る。
2. **「後で読む」セクションを抽出**:
   - 対象ノートに対して `read-note` を **並列で** 実行する（読み込みなので競合しない）。
   - 本文中で `読了判定: 後で読む` を含むセクションだけリスト化（inbox-capture が各セクションに書き込んだフィールドを参照する）。
3. **セクションごとに2択判定**（ユーザーに確認しながら進める）:
   - **育てる** → 個別ノート化フロー（下記）
   - **捨てる** → 日次まとめから該当セクションを削除のみ
4. **判定済みセクションを日次まとめから削除**: 残りの本文で `update-note`。日次まとめが完全に空になったら `delete-note`
5. **NotebookLM 昇格チェック**: タグ単位で3本以上溜まったものがあれば `notebooklm-judge` の実行を提案

## 「育てる」フロー

1. AI: 該当セクションを `create-note` で個別ノート化 (status: `active`)
2. ユーザー: 元記事を深読み(30分〜)
3. ユーザー: 自分の考察を1〜3行ノート末尾に追記（検索性の源泉）
4. AI: タグを決定し、`update-note` を **1回だけ** 呼んで `tagIds` と `bookId` を同時に指定する
   - タグ付け = 下記「タグの決め方」に従う
   - 移動先 = 上記「移動先ノートブック」から選ぶ
   - MCP 起動コスト削減のため、必ず 2 回 (`tagIds` 用 + `bookId` 用) に分けず 1 回で済ませる

## タグについて

- タグは **NotebookLM 昇格の単位** = **サブテーマ粒度**（例: `tech/AI` 配下なら `harness-eng`, `vibe-coding`, `prompt-caching`）
- 1ノート = 1タグ
- タグ付けはこのスキル（育てる時）のみ。inbox-capture 時点では付けない

## タグの決め方

1. `list-tags` で既存タグ一覧を取得
2. 記事内容と**サブテーマ粒度**で最も合致する既存タグを選ぶ
3. 既存タグで対応できない場合のみ `create-tag` で新規作成:
   - 作成基準: 「今後も同テーマの記事が継続的に増える見込みがある」場合のみ
   - 一発ネタ・特定イベント限定の記事にはなるべく既存タグで対応する（タグの乱立防止）
   - 色はランダムに選ぶ: `red` / `orange` / `yellow` / `olive` / `green` / `teal` / `blue` / `violet` / `purple` / `pink` / `brown` / `grey` / `black`
- ノートブック単位（`tech/AI` 等）は NotebookLM トピックとしては大きすぎる

## タイムアウトとリトライ方針

- **MCP 呼び出し (Stateless = Antigravity)**: タイムアウト 60秒（`op run` 認証 + `npx` 起動を含む）。失敗時は1回だけリトライしてよい
- **MCP 呼び出し (Persistent = Claude / Codex)**: タイムアウト 30秒。失敗時は1回だけリトライしてよい

## 注意

- 個別ノート化したら元の日次まとめからセクションを必ず削除する
- 「育てる」の深読みはこのセッション中に終わらなくてよい（後で時間を取る）
- 1セッションで全件こなさなくてよい
