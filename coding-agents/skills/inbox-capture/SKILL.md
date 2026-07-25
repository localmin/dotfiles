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
- **sandbox下でのosascript失敗に注意**: `list-windows.sh` / `window-urls.sh` は内部で osascript を使い Chrome を操作するが、sandbox環境では Apple Events 通信がブロックされ、典型的な "Operation not permitted" ではなく「アプリケーションは実行されていません (-600)」のような誤解を招くエラーを返すことがある。このエラーだけを見て Chrome 未起動と判断してはならない。まず `dangerouslyDisableSandbox` を付けて再実行し、それでも失敗する場合のみ Chrome 未起動を疑う。

## 当日まとめノートのフォーマット

- タイトル: `inbox YYYY-MM-DD`(例: `inbox 2026-05-02`)
- bookId: inbox ノートブックの **book `_id`**（`inbox` という表示名をそのまま渡さないこと）。`create-note` の `bookId` は `^(book:|trash$)` パターンの実IDが必須で、表示名 `inbox` や `book:inbox` では通らない。**`list-notebooks` を呼び、`name == "inbox"` の `_id`（例 `book:51GBqxKj`）を引いて渡す**。この解決は系統B（ノート ID 解決）内で新規作成が確定したときに行う。
  - 注意: `search-notes` の `book:inbox` は**表示名フィルタ**なのでそのまま使える。`bookId` 引数（`create-note` / `update-note`）だけが実 `_id` を要求する。混同しない。
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
       - **その他（HTML 記事）**（zenn / Qiita / speakerdeck / ニュース等）は **`ax`**（`ax <URL> --md` で本文を markdown 取得。CLAUDE.md「Web 取得・HTML 抽出は `ax` を既定にする」の使用地点側の徹底）。WebFetch は ax で取れないときのフォールバック。
         - `ax --md` は既定で出力を capped（末尾に「N more hidden — `--all` / `--offset` / `--budget`」の注記が出る）。**要約には既定出力で足りるので `--all` で全文を引かない**（トークン浪費）。既定で足りない長文だけ `--budget <T>` で上限を上げる。
       - **PDF**（`.pdf` で終わる URL、または `ax --md` に投げたら本文でなく `%PDF-...` の生バイナリが返ってきたもの。**ホストに依存せず content-type で判定する** — TDnet / 論文 / スライド PDF 等）は **`ax --md` で読めない**。`ax <URL> -o <一時ファイル.pdf>` で保存し、**Read ツールの `pages` 引数**で読む（10 ページ超は `pages` 指定必須、1 回最大 20 ページ）。表紙・目次・冒頭数ページで要約に足りることが多いので全ページを読み込まない。
     - バッチを組むとき、先頭で URL を「GitHub 系 / HTML / PDF」に振り分けてから流すこと（GitHub 系 → `gh`、HTML → `ax --md`、PDF → `ax -o` + Read）。GitHub の本文を `gh` 以外で取ると薄く要約され、後段の週次判定を誤らせる。
     - **取得失敗の扱い**: fetch はコード列挙でなく**カテゴリ**で判定する — 4xx（404 等）/ 5xx / ネットワークタイムアウト / レート制限（429）はいずれも**リトライせず**「取得失敗」リストへ積んで続行。**GitHub 系が `gh` で失敗しても WebFetch にフォールバックしない**（薄い要約で代替するより、欠落として明示する方が週次判定を誤らせない）。取得失敗リストはノート末尾に `## 取得失敗` セクションとしてまとめる。
   - 系統B（当日ノート準備）: 下記「ノート ID 解決ロジック」に従って `_id` と `_rev` を取得する。
3. **Phase 2 (1回のみ): 一括書き込み**:
   - Phase 1 で揃った全セクションをまとめて当日ノートに追記する。
   - 新規作成の場合は `create-note` (必ず `status: "active"` を指定、`bookId` は上記「当日まとめノートのフォーマット」の通り `list-notebooks` で引いた実 `_id`) を呼び出し、作成された `_id` をキャッシュ (`~/.cache/inbox-capture/today-note-id`) に保存する。
   - 既存ノートへの追記の場合は `update-note` を呼ぶ。`update-note` には `_id` と `_rev` が必須。
   - 書き込み時の MCP 呼び出しは **1回だけ** にすること。
   - 追記時は `read-note` で取得した既存本文を絶対に消さず、末尾にセクションを追加するだけにする。

### ノート ID 解決ロジック (Phase 1 系統B)

```
1. ~/.cache/inbox-capture/today-note-id を読む
2a. キャッシュあり: read-note を実行
    - 失敗 (404 / not_found / 削除済み) → キャッシュを破棄し 2b へフォールバック
    - 成功 → 取得した title が `inbox <今日の日付>` と一致するか必ず検証する
        - 一致 → _id, _rev, 本文を確定して終了 (MCP 1回)
        - 不一致（日付をまたいでキャッシュが前日以前のノートを指していた等）
          → キャッシュを破棄し 2b へフォールバック
2b. キャッシュなし or フォールバック: search-notes で
    `book:inbox title:"inbox YYYY-MM-DD"` を検索
    - ヒット → _id をキャッシュに保存し、read-note で本文と _rev を取得 (MCP 2回)
    - ミス  → 新規作成扱い。**bookId を `list-notebooks` で解決**（`name == "inbox"` の実 `_id`。「当日まとめノートのフォーマット」参照）してから、Phase 2 で create-note を呼ぶ (MCP 1回)
```

**read-note の成功は「今日のノートである」ことを保証しない**（ノート自体は削除されず存在し続けるため）。title 検証を省略しないこと。

呼び出し回数まとめ:
- ベストケース（キャッシュヒット かつ title 一致）: read-note + update-note = **2 回**
- キャッシュミス / 無効 / title 不一致: search-notes + read-note + update-note = **3 回**
- 当日初回: search-notes + create-note = **2 回**

## 処理フェーズの設計

URL fetch と要約生成は記事ごとに独立しているため並列化できる。さらに MCP の起動コストを隠すため、ノート ID 解決も Phase 1 内で同時に走らせる。Inkdrop への書き込みは競合を防ぐため Phase 2 で一括で行う。

```
Phase 1 — 並列
  系統A: 全 URL を fetch → 要約 → 読了判定 (5〜10 件ずつバッチ)
         ※ GitHub 系は gh、HTML は ax --md、PDF は ax -o + Read の pages で本文取得（WebFetch はフォールバック）
         ※ 404 / 429 / タイムアウトはリトライせず「取得失敗」リストに追加して続行
  系統B: ノート ID 解決ロジックを実行し _id / _rev / 既存本文を取得
         ※ read-note 失敗時、または成功しても title が今日の日付と不一致な場合は search-notes にフォールバック

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
