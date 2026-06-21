---
name: inbox-capture
description: Chromeウィンドウを選択して全タブのURLを取得し、記事を要約してInkdropのinbox当日まとめノート（inbox YYYY-MM-DD）にセクションとして追記する。同日2回目以降は既存ノートに追記。日次運用想定。
---

# inbox-capture

Chrome ウィンドウから URL を取得し、記事を fetch して要約し、Inkdrop の inbox ノートブックの **当日まとめノート** に追記する。

## Inkdrop MCP の使用方法と注意点

スキル開始前に、各CLIにおける Inkdrop MCP の呼び出し方針を確認すること。
特に 1Password (`op run`) による認証が走るため、不要なタイミングでの認証ポップアップを防ぐ必要がある。

- **Claude Code**: `~/dotfiles/` から `claude` を起動する（`~/dotfiles/.mcp.json` で自動読み込み）
- **Codex**: `~/dotfiles/coding-agents/codex/config.toml` の `enabled = false` を削除
- **Antigravity**:
  Antigravity CLI では `antigravity mcp enable inkdrop` による常時有効化は行わないこと（関係ない操作でも 1Password が立ち上がるのを防ぐため）。
  代わりに、一時的なスクリプト等を生成し、以下のように `run_shell_command` 経由で MCP サーバーの stdio に直接 JSON-RPC を流し込んで単発実行（Stateless Invocation）すること。
  - 短いクエリ（検索など）の例: `echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search-notes","arguments":{"keyword":"..."}}}' | op run --env-file=~/dotfiles/coding-agents/inkdrop.op.env -- npx --prefer-offline -y @inkdropapp/mcp-server`
  - 長いテキスト（ノート更新など）の例: 下記の「安全なJSON構築」セクションを参照。

## 入力

なし（起動後にスクリプトで Chrome ウィンドウを選択する）

特定の URL を直接指定したい場合のみ引数として渡す（例外的な用途）。

## URL 取得

スキル起動後、まず以下のスクリプトを実行してウィンドウ選択・URL 取得を行う:

```bash
~/dotfiles/coding-agents/skills/inbox-capture/scripts/window-urls.sh
```

- ウィンドウが複数ある場合は fzf でインタラクティブ選択
- macOS + Google Chrome 専用

## 当日まとめノートのフォーマット

- タイトル: `inbox YYYY-MM-DD`(例: `inbox 2026-05-02`)
- bookId: `inbox`
- 本文構造:

```markdown
# inbox 2026-05-02

## [記事タイトル1]

- URL: https://...
- 読了判定: 要約で十分 / 後で読む / 即読了

### 要約

[5〜10行。読み返して「なぜ保存したか」「何が書かれているか」が両方分かる粒度]

### メモ



---

## [記事タイトル2]

...
```

## 手順と最適化

Antigravity CLI における Stateless MCP 呼び出しは起動コスト（認証・NPM レジストリへの問い合わせ等）が大きいため、**呼び出し回数を最小化** し、かつ **fetch と並列に走らせて起動コストを隠す** こと。

1. **URL 取得**:
   - 各種エージェント環境（Antigravity / Claude / Codex）では、ターミナルを占有する `fzf` が正常に動作しない（フリーズする）ため、`window-urls.sh` を引数なしで実行してはならない。
   - 代わりに、必ず以下の手順でユーザーにウィンドウを選択させること：
     1. 以下のコマンドで開いているChromeウィンドウの一覧を取得する。
        ```bash
        ~/dotfiles/coding-agents/skills/inbox-capture/scripts/list-windows.sh
        ```
     2. 取得したウィンドウ一覧をチャット上で提示し、「どのウィンドウ（番号）を処理しますか？」とユーザーに入力を求める。
     3. ユーザーが番号を指定したら、`window-urls.sh <番号>` のように引数付きで実行してURLリストを取得する。
2. **Phase 1 (並列): fetch + 要約 + 当日ノート準備**:
   - 以下の 2 系統を **並列に** 走らせる。MCP 起動コストを fetch 待ち時間で隠すのが狙い。
   - 系統A（fetch+要約）: URL群を 5〜10 件ずつバッチ処理して fetch → 要約 → 読了判定。
     - **取得方法は URL のホスト「ファミリ」で分岐する**（特定パターンの列挙ではなく分類で判断する。列挙だと未掲載のサブパスが未定義になる）:
       - **GitHub 系**（`github.com` / `gist.github.com` / `raw.githubusercontent.com` の**全パス**）は **`gh` で取る**。WebFetch は使わない（文字数が多いと取得漏れ・要約精度低下が起きるため。CLAUDE.md「GitHub 参照は `gh` 優先」の使用地点側の徹底）。URL 種別ごとのエンドポイント対応:
         - repo ルート `github.com/<o>/<r>` → `gh api repos/<o>/<r>/readme --jq '.content' | base64 --decode`
         - ファイル `…/blob/<ref>/<path>` および `raw.githubusercontent.com/<o>/<r>/<ref>/<path>` → `gh api 'repos/<o>/<r>/contents/<path>?ref=<ref>' --jq '.content' | base64 --decode`
         - gist → `gh gist view <id> -r`
         - issues / pull / releases / discussions → 対応する `gh issue view` / `gh pr view` / `gh release view` または `gh api`
         - **上記に当てはまらない github 所有ホストのパスも、WebFetch には流さず最も近い `gh api` リソースで取る**（既定ブランチ）。
         - 本文が長い場合は一時ファイルに落として Read で読む。
       - **その他**（zenn / Qiita / speakerdeck / ニュース等）は WebFetch。
     - バッチを組むとき、先頭で URL を「GitHub 系 / その他」に振り分けてから流すこと。一律 WebFetch に流す運用は禁止（GitHub の本文は WebFetch だと薄く要約され、後段の週次判定を誤らせる）。
     - **取得失敗の扱い**: fetch はコード列挙でなく**カテゴリ**で判定する — 4xx（404 等）/ 5xx / ネットワークタイムアウト / レート制限（429）はいずれも**リトライせず**「取得失敗」リストへ積んで続行。**GitHub 系が `gh` で失敗しても WebFetch にフォールバックしない**（薄い要約で代替するより、欠落として明示する方が週次判定を誤らせない）。取得失敗リストはノート末尾に `## 取得失敗` セクションとしてまとめる。
   - 系統B（当日ノート準備）: 下記「ノート ID 解決ロジック」に従って `_id` と `_rev` を取得する。
3. **Phase 2 (1回のみ): 一括書き込み**:
   - Phase 1 で揃った全セクションをまとめて当日ノートに追記する。
   - 新規作成の場合は `create-note` (必ず `status: "active"` を指定) を呼び出し、作成された `_id` をキャッシュ (`~/.cache/inbox-capture/today-note-id`) に保存する。
   - 既存ノートへの追記の場合は `update-note` を呼ぶ。`update-note` には `_id` と `_rev` が必須。
   - 書き込み時の MCP 呼び出しは **1回だけ** にすること。
   - 追記時は `read-note` で取得した既存本文を絶対に消さず、末尾にセクションを追加するだけにする。

### ノート ID 解決ロジック (Phase 1 系統B)

```
1. ~/.cache/inbox-capture/today-note-id を読む
2a. キャッシュあり: read-note を実行
    - 成功 → _id, _rev, 本文を取得して終了 (MCP 1回)
    - 失敗 (404 / not_found / 削除済み) → キャッシュを破棄し 2b へフォールバック
2b. キャッシュなし or フォールバック: search-notes で
    `book:inbox title:"inbox YYYY-MM-DD"` を検索
    - ヒット → _id をキャッシュに保存し、read-note で本文と _rev を取得 (MCP 2回)
    - ミス  → 新規作成扱い。Phase 2 で create-note を呼ぶ (MCP 1回)
```

呼び出し回数まとめ:
- ベストケース（キャッシュヒット）: read-note + update-note = **2 回**
- キャッシュミス / 無効: search-notes + read-note + update-note = **3 回**
- 当日初回: search-notes + create-note = **2 回**

## 処理フェーズの設計

URL fetch と要約生成は記事ごとに独立しているため並列化できる。さらに MCP の起動コストを隠すため、ノート ID 解決も Phase 1 内で同時に走らせる。Inkdrop への書き込みは競合を防ぐため Phase 2 で一括で行う。

```
Phase 1 — 並列
  系統A: 全 URL を fetch → 要約 → 読了判定 (5〜10 件ずつバッチ)
         ※ github.com のリポジトリ/gist は WebFetch ではなく gh で本文取得
         ※ 404 / 429 / タイムアウトはリトライせず「取得失敗」リストに追加して続行
  系統B: ノート ID 解決ロジックを実行し _id / _rev / 既存本文を取得
         ※ read-note 失敗時は search-notes にフォールバック

Phase 2 — 書き込み（1回のみ）
  全セクションをまとめて当日ノートに append
  → update-note または create-note を 1 回だけ呼ぶ
```

**バッチサイズの目安**: 5〜10 件。これ以上は fetch のレート制限に引っかかることがある。

読了判定:
- `要約で十分` — 長すぎ・概観で足りる（日次完了、週次対象外）
- `後で読む` — 深読み価値あり、週次「育てる」候補
- `即読了` — 短文・その場で読了（日次完了、週次対象外）

## タイムアウトとリトライ方針

- **fetch (Web 取得 / gh 取得)**: タイムアウト 10秒。4xx / 5xx / タイムアウト / 429（レート制限）はカテゴリ問わずリトライしない（失敗リストに積んで続行）。GitHub 系の `gh` 失敗時も WebFetch にフォールバックしない。詳細は Phase1 系統A「取得失敗の扱い」を参照。
- **MCP 呼び出し (Stateless = Antigravity)**: タイムアウト 60秒（`op run` 認証 + `npx` 起動を含む）。失敗時は1回だけリトライしてよい
- **MCP 呼び出し (Persistent = Claude / Codex)**: タイムアウト 30秒。失敗時は1回だけリトライしてよい

## 要約の粒度

- 5〜10行(以前の3〜5行から拡大)
- 「何が書かれているか」 + 「なぜ気になるか」が両方伝わる
- ただし**長大な記事は要約だけで完結する量**にする(深読み判定は週次で)

## 読了判定の使い分け

dailyの時点で読むかどうかを判定する。**「即読了」と「要約で十分」はそこで完了**(週次レビューで再判定しない)。「後で読む」だけが週次レビューの対象になる。

| 判定 | 目安 | 週次での扱い |
|---|---|---|
| 即読了 | 全文1,000字程度、その場で読み切れた | 対象外(完了) |
| 要約で十分 | 全文5,000字超、関心の周辺、概観で足りそう | 対象外(完了) |
| 後で読む | 関心の中心、深読みで知識化したい | weekly-review で 育てる/捨てる 判定 |

## 注意事項

- **`create-note` 時は必ず `status: "active"` を指定する**。省略するとステータスが `none` になり Inkdrop で表示されない
- **`update-note` 実行時の引数**: 更新には必ず対象ノートの `_id` と `_rev` (現在のリビジョン番号) が必要。`read-note` の結果からこれらを取得して引数に渡すこと（`noteId` という引数名ではないので注意）。
- **タグは付けない**。タグは週次レビューで「育てる」判定して昇格したときのみ付ける
- メモは空欄でOK(後から追記用)
- **追記時の本文更新は 既存内容を絶対に消さない こと**(`read-note` の結果に末尾追加するだけ)

## ⚠️ 重要: エラーハンドリングと安全な実行（1Password認証爆発の防止）

- **安易なリトライの禁止**: `op run` を介したコマンド実行が失敗した際（例: 環境変数パスのミス、JSONフォーマットエラー、コマンドインジェクション警告など）、**原因を修正せずにリトライを繰り返してはならない**。短時間の連続失敗は、ユーザーに大量の1Password認証ポップアップを発生させる。
- **安全なJSON構築 (jqの必須使用)**: 長いMarkdownテキスト（改行やクォートを含む）をMCPサーバーへ送信する際、シェル上で文字列補間（例: `echo '{"body": "'$BODY'"}'`）を行ったり、Python等の外部スクリプトで回避しようとしてはならない。**必ず `jq -nc --rawfile body <ファイルパス> '{...}'` を使用して安全にJSONエンコードおよび1行化（minify）を行うこと**。
  - 成功例: `jq -nc --rawfile body ./tmp.md '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create-note","arguments":{"body":$body,"title":"inbox ...","bookId":"book:...","status":"active"}}}' | op run --env-file=~/dotfiles/coding-agents/inkdrop.op.env -- npx --prefer-offline -y @inkdropapp/mcp-server`
- **テストノートの作成禁止**: 認証やペイロードのエラーを調査するために、本番のInkdropデータベースに中身のないテストノート（例: `{"body": "test"}`）を作成してはならない。どうしても作成してしまった場合は、速やかに `update-note` で `status: "dropped"` に更新してクリーンアップすること。エラーの調査は、`op run` を介さないローカルでの JSON 文字列検証（`jq` の出力確認など）に留めること。
