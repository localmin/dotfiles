---
name: inbox-capture
description: Chromeウィンドウを選択して全タブのURLを取得し、記事を要約してInkdropのinbox当日まとめノート（inbox YYYY-MM-DD）にセクションとして追記する。同日2回目以降は既存ノートに追記。日次運用想定。
---

# inbox-capture

Chrome ウィンドウから URL を取得し、記事を fetch して要約し、Inkdrop の inbox ノートブックの **当日まとめノート**（`inbox YYYY-MM-DD`）に追記する。入力は不要（起動後にウィンドウを選ばせる）。特定 URL を直接処理したいときだけ引数で渡す。

一般的な sandbox / `gh` 優先 / `$TMPDIR` で sandbox 判定しない、等の罠は CLAUDE.md の該当ルールに従う。本 skill はそれらの **inbox 固有の現れ方**だけを各所に書く。

## 前提: Inkdrop MCP の呼び出し方針

1Password（`op run`）の認証が走るため、CLI ごとに呼び出し方を確認してから始める。

- **Claude Code**: `~/dotfiles/` から `claude` を起動する（`~/dotfiles/.mcp.json` が自動で読まれる）
- **Codex**: `~/dotfiles/coding-agents/codex/config.toml` の `enabled = false` を削除
- **Antigravity**: `antigravity mcp enable inkdrop` による常時有効化はしない（無関係な操作でも 1Password が立ち上がる）。代わりに MCP サーバーの stdio へ JSON-RPC を直接流す単発実行にする。
  - 短いクエリ: `echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search-notes","arguments":{"keyword":"..."}}}' | op run --env-file=~/dotfiles/coding-agents/inkdrop.op.env -- npx --prefer-offline -y @inkdropapp/mcp-server`
  - 長いテキスト（ノート本文）は「1Password 認証爆発の防止」の `jq --rawfile` 形式を必ず使う。

`jq --rawfile` 経路は Antigravity 専用ではない。**どの CLI でも、既存本文が大きいノートへの追記はこの経路**（理由は Phase 2）。

## Phase 0: URL 取得

1. ウィンドウ一覧: `~/dotfiles/coding-agents/skills/inbox-capture/scripts/list-windows.sh`
2. 一覧をチャットに**全件そのまま**提示し、「どのウィンドウ（番号）を処理しますか？」と聞く。
3. 指定番号で `~/dotfiles/coding-agents/skills/inbox-capture/scripts/window-urls.sh <番号>` を実行。

- **`window-urls.sh` を引数なしで実行しない**: fzf に落ちてターミナルを占有しフリーズする。番号は必ず聞いてから渡す。
- **sandbox 下の osascript 失敗に注意**: 両スクリプトは内部で osascript を使う。sandbox では Apple Events がブロックされ「アプリケーションは実行されていません (-600)」という誤解を招くエラーになる。**これを Chrome 未起動と判断しない**。まず `dangerouslyDisableSandbox` で再実行し、それでも失敗するときだけ未起動を疑う。
- **ウィンドウ一覧が空（exit 0 で出力なし）なら残留 playwright Chrome を疑う**: playwright MCP は `--user-data-dir=~/Library/Caches/ms-playwright-mcp/...` で別インスタンスの Chrome を起動する。残っていると AppleScript の宛先がそちらへ向き `count of windows` が 0 を返す（エラーにならない）。判別は `pgrep -f "ms-playwright-mcp/mcp-chrome"`、当たったら `browser_close` で閉じてから再実行する。**使ったブラウザは必ず `browser_close` で閉じる**（閉じ忘れは次回の Phase 0 を壊す。これが本 skill の browser_close 規定の正本）。
- macOS + Google Chrome 専用。

## Phase 1（並列）: fetch + 要約 ∥ 当日ノート準備

系統 A と B を**並列**に走らせる。MCP の起動コストを fetch の待ち時間で隠すのが狙い。

### 系統A: fetch → 要約 → 読了判定

**全 URL を 1 回のコマンドで並列 fetch する。URL ごとに `ax` / `gh` を個別 Bash 呼び出ししない。**

```bash
~/dotfiles/coding-agents/skills/inbox-capture/scripts/fetch-batch.sh -o <出力ディレクトリ> <URLリストファイル>
```

- **理由（実測）**: 遅さの原因は `ax` ではなく往復回数。個別呼び出しは 12 件で 35 tool use / 257 秒、一括並列は **6 秒 / 1 tool call**。`ax` をやめず往復を畳む。
- 出力は `manifest.tsv`（`idx / kind / status / title / path / url`）+ URL ごとの `NNN.md` / `NNN.pdf`。
- **セクション見出しは `title` 列をそのまま使う。記事タイトルを自分で作文しない**（HTML はページの `<title>`、それ以外は本文の先頭見出し）。`title` が空のときのフォールバック: **PDF** は1ページ目の表題、**HTML / GitHub** は本文の先頭見出し。いずれも作文でなく本文から起こしたことを該当記事の `### メモ` に1行残す。要約は出力ファイル群を **Read で並列に読んで**行う（PDF は Read の `pages` 引数。10 ページ超は `pages` 必須・1回最大20。全ページは読まない）。

`status` の意味と対応:

| status | 意味 | 対応 |
|---|---|---|
| `ok` | 本文取得済み・打ち切りなし | 要約へ |
| `partial` | ax が「N more result(s) hidden」を報告＝**末尾が欠けている** | `-b` を上げて該当 URL だけ取り直す（結論は末尾に多い） |
| `empty` | 取得はできたが本文が空（JS 描画 SPA） | **playwright / chrome-devtools でスナップショットを取り自分で抽出・要約**（`.playwright-mcp/` に残る旨を `### メモ` に1行。gitignore 済み。使ったら Phase 0 のとおり `browser_close`）。WebFetch は playwright も使えないときの最終手段 |
| `failed` | 取得失敗。理由は `NNN.err` | 下記「取得失敗の扱い」 |

- **`status` は自動検出の下限であって十分性の保証ではない**。`ok` でも本文が薄いなら `empty` と同じエスカレーション（playwright）に載せる。判断するのは status でなく読んだ自分。
- 主な引数: `-b <budget>`（HTML の `ax --budget`、既定 6000）/ `-j <並列数>`（既定 8。429 が出るホストは下げる）/ `-o <出力先>`。URL は 1 回で何件でも可（制御するのは同時接続数）。
- **GitHub URL を含むときは `dangerouslyDisableSandbox` を付ける**（sandbox は `~/.config/gh` 読み取りを拒否し `gh` が全滅。404 でも認証切れでもないので「取得失敗」に積まない）。inbox 固有の注意:
  - **`sandbox.excludedCommands` の `gh *` は効かない**: 照合はコマンド先頭に対してで、`fetch-batch.sh` の**内部から**呼ばれる `gh` は sandbox の外に出ない。スクリプト自体が除外対象でない限り「`gh *` があるから大丈夫」の根拠にしない。
  - **`dangerouslyDisableSandbox` が拒否されたら sandbox 内で走らせて終わりにしない**: GitHub 系だけ静かに失敗する。① GitHub 系 URL を別リストに分け `gh` で取り直す（`gh` 単体なら `excludedCommands` の `gh *` が効く）② それも拒否ならユーザーに permission 追加を求める、の順で対応し、**取れなかった旨を必ず報告する**。

**振り分け規則**（スクリプトが URL から自動判定。`--plan <URL>` で判定だけ確認、回帰テストは `scripts/test-fetch-batch.sh`）:

| ファミリ | 判定 | 取得手段 |
|---|---|---|
| GitHub 系 | `github.com` / `gist.github.com` / `raw.githubusercontent.com` の**全パス** | `gh`（repo ルート→readme、blob/tree→contents、gist→`gh gist view`、issues/pull/releases/discussions→対応コマンド。未対応パスも最も近い `gh api` に落とす） |
| PDF | `.pdf` 終端、または本文が `%PDF-` で始まる（**content-type で判定**） | `ax -o` で保存 → Read の `pages` |
| その他 HTML | zenn / Qiita / ニュース等 | `ax --md` |

ファミリで判断し既知ホストの列挙で判断しない（列挙だと未掲載サブパスが未定義になる）。**GitHub 系を `gh` 以外で取ると本文が薄くなり週次判定を誤らせる。**

**取得失敗の扱い**（正本。系統A の `failed` とタイムアウト節はここを参照）: 4xx / 5xx / タイムアウト / 429 は**カテゴリ問わず同一条件での再試行をしない**。条件を変えた取り直し（`partial`→`-b` 引き上げ、`empty`→playwright）は再試行に当たらず、各 status の規定どおり実施してよい。禁止は「同じコマンドをもう一度打つ」ことだけ。失敗はリストに積んで続行し、ノート末尾に `## 取得失敗` セクションとしてまとめる。各行に **`NNN.err` のエラー原文を必ず併記**（`- <URL> — ax: fetch failed: 429`）。分類は読み手に委ね、記録側は情報を落とさない。**GitHub 系が `gh` で失敗しても WebFetch にフォールバックしない**（薄い要約で埋めるより欠落として明示する方が誤らせない）。

**守るべき不変条件: 生本文をこのタスク後も残る文脈に到達させない**。生本文は tool result に乗ると要約後もログに残るので、**inline fetch は件数によらず必ず汚染する**。立場は自己認識で判定せず、**プロンプトの明示 signal で判定する**:

- **プロンプトに `ISOLATED-EXECUTOR` が無ければ自分は main 側**。系統A ごと `general-purpose` subagent に隔離し、main は完成セクション（要約 + 読了判定）だけ受け取る（`parallelization` skill）。dispatch 時、subagent プロンプト冒頭に必ず: `ISOLATED-EXECUTOR: あなたは隔離済みの実行者です。系統A をさらに subagent へ再委譲せず inline で実行してください。`
- **`ISOLATED-EXECUTOR` があれば inline で実行**（再委譲は 1 段で止まる）。宣言が無くても「再委譲するな / あなたが専任」に相当する指示があれば inline に倒し、その際は**生本文がこの文脈に乗ったことを報告に明示する**。
- **12 件超は subagent 自体を複数並列に dispatch**（fetch 時間は潰れているので残るは要約の思考時間）。URL を 6〜8 件ずつに分け同一ブロックで同時起動、main は返ったセクションを URL 順に連結。少数なら 1 subagent でよい。

### 系統B: 当日ノートの `_id` / `_rev` 解決

「今日の日付」は**セッションに与えられた日付を唯一の基準にする**（`date` を引き直さない。日付をまたぐと分岐が揺れる）。

**キャッシュ検証に MCP の `read-note` を直接使わない。`scripts/note-head.sh` を使う**:

```bash
~/dotfiles/coding-agents/skills/inbox-capture/scripts/note-head.sh \
  -o <出力ディレクトリ> --expect-title "inbox <今日の日付>" <キャッシュの note:ID>
```

stdio 経路で `read-note` を呼び、**本文を `<出力先>/body.md` に書いて標準出力には出さない**。文脈に載るのは `id / rev / title / bookId / chars / body_path` の6行だけ。title 検証も済ませ結果を exit code で返す:

| exit | 意味 | 次の動作 |
|---|---|---|
| 0 | 今日のノート。`rev` と `body_path` 確定 | Phase 2 の追記へ（MCP 1回） |
| 3 | ノートは在るが title が別日 | キャッシュ破棄し 2b へ |
| 4 | ノートが無い（404 / not_found） | キャッシュ破棄し 2b へ |
| 5 | 呼び出し未完了（タイムアウト / 認証 / 接続断） | **キャッシュを破棄しない**。1回だけ再試行、駄目なら中断してユーザーに報告 |
| 2 | 引数エラー | 呼び出しを直す |

- **`read-note` を直接呼ぶと既存本文が丸ごと文脈に載る**（当日ノートは 20 件で 60,000 字超。以降の作業が潰れる。実測 23,743 字浪費）。title を確かめたいだけなら本文は要らない。**`--expect-title` を省略しない**（`read-note` の成功は「今日のノート」を保証しない。ノートは削除されず残り続ける）。1Password が走るため sandbox 外で実行（`dangerouslyDisableSandbox`）。

キャッシュが無い / 破棄した場合（2b）: `search-notes` で `book:inbox title:"inbox YYYY-MM-DD"` を検索 → ヒットなら `_id` をキャッシュ保存し `note-head.sh` で本文と `_rev` を取得 / ミスなら新規作成扱い（`list-notebooks` で bookId を解決し Phase 2 で create-note）。回帰テストは `scripts/test-note-head.sh`（MCP を stub。オフライン・認証なし。`TMPDIR` が書けない環境は `TEST_TMPDIR=<書ける場所>`）。

## Phase 2（1回のみ）: 一括書き込み

Phase 1 で揃った全セクションをまとめて当日ノートに書く。**MCP 呼び出しは 1 回だけ**。

- 新規作成: `create-note`。**`status: "active"` を必ず指定**（省略すると `none` になり表示されない）。作成された `_id` を `~/.cache/inbox-capture/today-note-id` に保存する（**キャッシュ書き込みは sandbox 内で失敗**する＝`~/.cache` は書き込み許可外。`dangerouslyDisableSandbox` を付ける。恒久対策は settings.json の `sandbox.filesystem.allowWrite` に `~/.cache/inbox-capture` を追加、設定済み）。
- 追記: `update-note`。引数は `_id` と `_rev`（`noteId` ではない。`note-head.sh` の `id` / `rev` をそのまま使う）。**既存本文を絶対に消さず末尾にセクションを追加するだけ**。
  - **既存本文が大きいときは MCP の `body` 引数を使わない**: `update-note` は body 全文を引数に取り、既存本文（20 件で 60,000 字超）を main の文脈に載せてしまう。この規模では**全 CLI 共通で** `jq --rawfile` + stdio 経路（下記）を使う。
  - **連結はファイル上で行う**: 新セクションだけをファイルへ書き、`cat <body_path> <新セクション> > <連結先>` で繋いで `jq -nc --rawfile body <連結先>` に渡す。`body_path` は `note-head.sh` が書いた既存本文で**一度も文脈に載っていない**。文脈に置くのは追記する新セクションだけ。
- **`bookId` は inbox ノートブックの実 `_id`**（例 `book:51GBqxKj`。`^(book:|trash$)` 必須で表示名 `inbox` や `book:inbox` では通らない。`list-notebooks` の `name == "inbox"` から引く）。混同注意: `search-notes` の `book:inbox` は**表示名フィルタ**でそのまま使える。実 `_id` を要求するのは `create-note` / `update-note` の `bookId` だけ。
- **タグは付けない**（週次で「育てる」判定して昇格したときだけ）。

## ノート本文のフォーマット

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

- **要約は散文のみ。Mermaid 図・表は使わない**（`note-taking` skill は図を勧めるが、**日次要約ではこの skill が優先**。理由: 5〜10 行方針と衝突。図解は週次で「育てる」判定を受けて個別ノート化するとき）。
- **ノート間リンクは `[タイトル](inkdrop://note/<id>)`**（`note:` プレフィックスを落とす。`[[wiki-link]]` 記法は無い。詳細は `note-taking` skill）。
- 要約の粒度は 5〜10 行（「何が書かれているか」+「なぜ気になるか」）。長大な記事も**要約だけで完結する量**に留める（深読みは週次）。
- `### メモ` は**気づき・関連メモを自由に書いてよい欄**（取得上の注記・他ノートとの関連・後で確かめたい点など）。空欄でも可。人間も後から追記するので、**追記時に既存のメモを消さない**。

## 読了判定

日次の時点で読むかを決める。**「即読了」と「要約で十分」はここで完了**し週次で再判定しない。「後で読む」だけが週次の対象。

**関心軸を先に判定する**（分量軸と同時に見ると、短くて関心の中心にある記事がどちらにも当てはまる）:

1. **深読みして知識化したいか？** → Yes なら**分量に関わらず「後で読む」**。「誰の関心か」の参照元は、作業中リポジトリの `CLAUDE.md` と `.claude/plans/` の進行中タスク、既存 inbox で「後で読む」が付いた記事の傾向。推定なので**迷ったら理由を `### メモ` に1行**（週次で人間が覆せる）。
2. No のときだけ分量で振る → その場で読み切れた量なら「即読了」、そうでなければ「要約で十分」。

| 判定 | 目安 | 週次 |
|---|---|---|
| 即読了 | 取得本文 5,000 字以下でその場で読み切れた | 対象外（完了） |
| 要約で十分 | 取得本文 5,000 字超・関心の周辺・概観で足りそう | 対象外（完了） |
| 後で読む | 関心の中心・深読みで知識化したい | weekly-review で 育てる/捨てる |

字数は**取得した本文**（`NNN.md`）で測る（原文の長さは手元にない）。**`wc -m`（文字数）を使い `wc -c`（バイト数）と混同しない**（日本語は 1.7〜2.2 倍ずれ判定が1段狂う）。**PDF は `NNN.pdf` しか出ないのでページ数を代理指標に**（目安: 10 ページ以下で「即読了」相当）。非記事ページ（EC 商品一覧・検索結果・ダッシュボード等）は要約対象を**列挙の要点**（件数・分類・価格帯・在庫や締切）にし、分量軸は「一覧を見て判断が済むか」で読む。

## タイムアウト

- **fetch**: 10 秒（`fetch-batch.sh` が `ax -m 10` で強制。`gh` はタイムアウト指定なし）。リトライしない（「取得失敗の扱い」）。
- **MCP（Stateless = Antigravity）**: 60 秒（`op run` 認証 + `npx` 起動を含む）。失敗時 1 回だけリトライ可。
- **MCP（Persistent = Claude / Codex）**: 30 秒。失敗時 1 回だけリトライ可。

## ⚠️ 1Password 認証爆発の防止

- **原因を直さずにリトライしない**: `op run` 経由のコマンドが失敗したとき（環境変数パスのミス、JSON フォーマットエラー、コマンドインジェクション警告など）、修正せず再実行を繰り返すとユーザーに大量の 1Password 認証ポップアップが出る。
- **JSON は `jq` で組み立てる**: 長い Markdown を MCP へ送るとき、シェルの文字列補間（`echo '{"body": "'$BODY'"}'`）や Python 迂回をしない。**必ず `jq -nc --rawfile body <ファイル>` でエンコードと 1 行化**。例: `jq -nc --rawfile body ./tmp.md '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create-note","arguments":{"body":$body,"title":"inbox ...","bookId":"book:...","status":"active"}}}' | op run --env-file=~/dotfiles/coding-agents/inkdrop.op.env -- npx --prefer-offline -y @inkdropapp/mcp-server`
- **テストノートを作らない**: 認証やペイロード調査のために本番 DB へ空ノート（`{"body": "test"}` 等）を作らない。作ったら直ちに `update-note` で `status: "dropped"`。調査は `op run` を通さないローカルの `jq` 出力確認に留める。
