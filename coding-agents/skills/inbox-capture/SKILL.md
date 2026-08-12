---
name: inbox-capture
description: Chromeウィンドウを選択して全タブのURLを取得し、記事を要約してInkdropのinbox当日まとめノート（inbox YYYY-MM-DD）にセクションとして追記する。同日2回目以降は既存ノートに追記。日次運用想定。
---

# inbox-capture

Chrome ウィンドウから URL を取得し、記事を fetch して要約し、Inkdrop の inbox ノートブックの **当日まとめノート**（`inbox YYYY-MM-DD`）に追記する。

入力は不要（起動後にウィンドウを選ばせる）。特定 URL を直接処理したいときだけ引数で渡す。

## 前提: Inkdrop MCP の呼び出し方針

1Password（`op run`）の認証が走るため、CLI ごとに呼び出し方を確認してから始める。

- **Claude Code**: `~/dotfiles/` から `claude` を起動する（`~/dotfiles/.mcp.json` が自動で読まれる）
- **Codex**: `~/dotfiles/coding-agents/codex/config.toml` の `enabled = false` を削除
- **Antigravity**: `antigravity mcp enable inkdrop` による常時有効化はしない（無関係な操作でも 1Password が立ち上がるため）。代わりに `run_shell_command` から MCP サーバーの stdio へ JSON-RPC を直接流す単発実行（Stateless Invocation）にする。
  - 短いクエリ: `echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search-notes","arguments":{"keyword":"..."}}}' | op run --env-file=~/dotfiles/coding-agents/inkdrop.op.env -- npx --prefer-offline -y @inkdropapp/mcp-server`
  - 長いテキスト（ノート本文）は後述「1Password 認証爆発の防止」の `jq --rawfile` 形式を必ず使う。

`jq --rawfile` 経路は Antigravity 専用ではない。**どの CLI でも、既存本文が大きいノートへの追記はこの経路を使う**（理由は Phase 2 の「既存本文が大きいときは MCP ツールの `body` 引数を使わない」）。

## Phase 0: URL 取得

1. ウィンドウ一覧を取得する: `~/dotfiles/coding-agents/skills/inbox-capture/scripts/list-windows.sh`
2. 一覧をチャットに**全件そのまま**提示し、「どのウィンドウ（番号）を処理しますか？」と聞く。
3. 指定された番号で `~/dotfiles/coding-agents/skills/inbox-capture/scripts/window-urls.sh <番号>` を実行する。

- **`window-urls.sh` を引数なしで実行しない**: 引数なしだと fzf に落ちるが、エージェント環境ではターミナルを占有してフリーズする。番号は必ずユーザーに聞いてから渡す。
- **sandbox 下の osascript 失敗に注意**: 両スクリプトは内部で osascript を使う。sandbox では Apple Events がブロックされ、"Operation not permitted" ではなく「アプリケーションは実行されていません (-600)」という誤解を招くエラーになる。**これを見て Chrome 未起動と判断してはならない**。まず `dangerouslyDisableSandbox` を付けて再実行し、それでも失敗したときだけ未起動を疑う。
- **ウィンドウ一覧が空（exit 0 で出力なし）なら、残留 playwright Chrome を疑う**: playwright MCP は `--user-data-dir=~/Library/Caches/ms-playwright-mcp/...` で別インスタンスの Chrome を起動する。これが残っていると AppleScript の宛先がそちらへ向き、**`count of windows` が 0 を返す**（エラーにならないので Chrome 未起動にも全ウィンドウ閉鎖にも見える）。判別は `pgrep -f "ms-playwright-mcp/mcp-chrome"` が当たるかで、当たったら playwright の `browser_close` で閉じてから再実行する。**実際にこれで Phase 0 が空振りした**（`osascript` が 0 を返す一方 System Events は 2 ウィンドウを認識、という食い違いが出る）。
- macOS + Google Chrome 専用。

## Phase 1（並列）: fetch + 要約 ∥ 当日ノート準備

系統 A と B を**並列に**走らせる。MCP の起動コストを fetch の待ち時間で隠すのが狙い。

### 系統A: fetch → 要約 → 読了判定

**全 URL を 1 回のコマンドで並列 fetch する。URL ごとに `ax` / `gh` を個別 Bash 呼び出ししない。**

```bash
~/dotfiles/coding-agents/skills/inbox-capture/scripts/fetch-batch.sh -o <出力ディレクトリ> <URLリストファイル>
```

- **理由（実測）**: fetch はネットワーク待ちで、12 件でも逐次 16 秒 / 並列 3 秒しかかからない。所要時間のほぼ全部は「1 URL = 1 tool call = 1 モデル往復」のレイテンシで、個別呼び出しでは 12 件が 35 tool use / 257 秒かかったのに対し、一括並列では **6 秒 / 1 tool call** で終わる。**遅さの原因は `ax` ではなく往復回数**なので、`ax` をやめるのではなく往復を畳む。
- 出力は `manifest.tsv`（`idx / kind / status / title / path / url`）+ URL ごとの `NNN.md` / `NNN.pdf`。
- **セクション見出しは `title` 列をそのまま使う。記事タイトルを自分で作文しない**（HTML はページの `<title>`、それ以外は本文の先頭見出しが入る）。`title` が空のときのフォールバックは取得手段ごとに違う:
  - **PDF**: 1 ページ目の表題を使う（PDF に markdown 見出しはないので `title` 列は必ず空になる）
  - **HTML / GitHub**: 本文の先頭見出しを使う
  - いずれの場合も、作文ではなく本文から起こしたことを該当記事の `### メモ` に1行残す。要約はこのファイル群を **Read で並列に読んで**行う（Read も 1 ブロックに並べて同時発行する）。PDF は Read の `pages` 引数で読む（10 ページ超は `pages` 必須、1 回最大 20 ページ。表紙・目次・冒頭数ページで足りることが多いので全ページ読まない）。
- `status` の意味:
  - `ok` — 本文取得済み、打ち切りの報告なし
  - `partial` — ax が「N more result(s) hidden」を報告した＝**末尾が欠けている**。`-b` を上げて該当 URL だけ取り直す。記事の結論は末尾に多いので、部分取得のまま要約すると読了判定を誤る
  - `empty` — 取得はできたが本文が空（JS 描画の SPA）。**playwright / chrome-devtools でスナップショットを取り、自分で抽出・要約する**。WebFetch は playwright も使えないときの最終手段（弱いモデルの要約を経由するので忠実度が落ちる）。**playwright はスクラッチパッドへ書けず（許可ルート外）スナップショットを `<repo>/.playwright-mcp/` に残す**ので、使ったらその旨を該当記事の `### メモ` に1行残す（ファイル自体は gitignore 済み）。**使い終わったら必ず `browser_close` で閉じる**——閉じ忘れた Chrome インスタンスは次回以降の Phase 0 を壊す（上記「ウィンドウ一覧が空」参照）。subagent に系統A を委譲するときは、この1行を subagent のプロンプトにも入れる（閉じるのは起動した側の責任で、main からは見えない）
  - `failed` — 取得失敗。理由は `NNN.err`
- **`status` は自動検出の下限であって、十分性の保証ではない**。`ok` でも本文が要約に足りないほど薄いなら（SPA が一部だけ描画した等）、`empty` と同じエスカレーション（playwright / chrome-devtools）に載せる。判断するのは status ではなく読んだ自分。
- 主な引数: `-b <budget>`（HTML の `ax --budget`、既定 6000）/ `-j <並列数>`（既定 8。特定ホストで 429 が出るなら下げる）/ `-o <出力先>`。URL 総数は 1 回で何件渡してもよい（制御するのは同時接続数）。
- **GitHub URL を含むときは `dangerouslyDisableSandbox` を付けて実行する**: sandbox は `~/.config/gh` の読み取りを拒否し、`gh` が `failed to read configuration ... operation not permitted` で全滅する。これは 404 でも認証切れでもないので「取得失敗」に積んではならない。
  - **settings.json の `sandbox.excludedCommands` に `gh *` があっても効かない**: この照合はコマンド文字列の先頭に対して行われるため、`fetch-batch.sh` の**内部から**呼ばれる `gh` は sandbox の外に出ない。スクリプト自体が除外対象に入っていない限り、`gh *` の登録を「だから大丈夫」の根拠にしない。
  - **`dangerouslyDisableSandbox` が permission 側で拒否されたら、そのまま sandbox 内で走らせて終わりにしない**: 拒否されると GitHub 系だけが静かに失敗する。その場合は ① GitHub 系 URL を別リストに分けて `gh` で個別に取り直す（`gh` 単体なら `excludedCommands` の `gh *` が効く）② それも拒否されたらユーザーに permission 追加を求める、の順で対応し、**取れなかった旨を必ず報告する**。
  - **sandbox 内かどうかは `$TMPDIR` では判断できない**（sandbox 外でも値が変わる）。確かめるなら `touch ~/.config/gh/__probe` が拒否されるかで見る。sandbox 外で `gh` が通ったことを「この制約は存在しない」の根拠にしない——過去に一度、この取り違えで誤った結論が出ている。

**振り分け規則**（スクリプトが URL から自動判定。`--plan <URL>` で fetch せず判定だけ確認でき、回帰テストは `scripts/test-fetch-batch.sh`）:

| ファミリ | 判定 | 取得手段 |
|---|---|---|
| GitHub 系 | `github.com` / `gist.github.com` / `raw.githubusercontent.com` の**全パス** | `gh`（repo ルート→readme、blob/tree→contents、gist→`gh gist view`、issues/pull/releases/discussions→対応コマンド。未対応パスも最も近い `gh api` に落とす） |
| PDF | `.pdf` 終端、または本文が `%PDF-` で始まる（**ホストでなく content-type で判定**） | `ax -o` で保存 → Read の `pages` |
| その他 HTML | zenn / Qiita / ニュース等 | `ax --md` |

ファミリ（分類）で判断し、既知ホストの列挙で判断しない——列挙だと未掲載のサブパスが未定義になる。**GitHub 系を `gh` 以外で取ると本文が薄くなり、後段の週次判定を誤らせる。**

**取得失敗の扱い**: 4xx / 5xx / タイムアウト / 429 は**カテゴリ問わず、同一条件での再試行をしない**。条件を変えた取り直し（`partial` に対する `-b` 引き上げ、`empty` に対する playwright への切り替え）は再試行に当たらず、上記の各 `status` の規定どおり実施してよい。禁止しているのは「同じコマンドをもう一度打つ」ことだけ。失敗リストに積んで続行し、ノート末尾に `## 取得失敗` セクションとしてまとめる。各行には **`NNN.err` のエラー原文を必ず併記する**（`- <URL> — ax: fetch failed: 429` の形）。一時的な 429 と恒久的な到達不能では週次での再訪価値が違うが、**分類は読み手に委ね、記録側は情報を落とさない**。**GitHub 系が `gh` で失敗しても WebFetch にフォールバックしない**（薄い要約で埋めるより、欠落として明示する方が週次判定を誤らせない）。

**守るべき不変条件: 生本文をこのタスク後も残る文脈に到達させない**。生本文は一度 tool result に乗ると要約後もログに残り続けるので、**inline fetch は件数によらず必ず汚染する**。系統A は「読む → 要約 → 生本文は捨てる」で生本文を後で使うことは一切ない。したがって:

立場は自己認識で判定しない（自分が subagent かどうかを確実に観測する手段はなく、「不明なら隔離」を既定にすると再委譲が無限に続く）。**プロンプトに置かれた明示 signal で判定する**:

- **プロンプトに `ISOLATED-EXECUTOR` の宣言がなければ、自分は main 側**。系統A ごと `general-purpose` subagent に隔離し、main は完成セクション（要約 + 読了判定）だけ受け取る（`parallelization` skill の適用）。
- **dispatch するとき、subagent へのプロンプト冒頭に必ず次の1行を入れる**:
  `ISOLATED-EXECUTOR: あなたは隔離済みの実行者です。系統A をさらに subagent へ再委譲せず inline で実行してください。`
- **プロンプトに `ISOLATED-EXECUTOR` があれば inline で実行する**。不変条件は既に満たされており、再委譲は 1 段で止まる。
- **宣言がなくても「再委譲するな」「あなたが専任の実行者だ」に相当する指示を受けているなら inline に倒す**（skill 経由でない起動——eval や手動 dispatch——では誰もこの1行を入れないため）。この経路で inline を選んだときは、**不変条件を破って生本文がこの文脈に乗ったことを報告に明示する**。

**12 件を超えるときは subagent 自体を複数並列に dispatch する**: fetch 時間は既に潰れているので、残るのは件数に比例する要約の思考時間。URL を 6〜8 件ずつに分けて同一ブロックで複数 subagent を同時起動し、main は返ってきたセクションを URL 順に連結する。少数のうちは 1 subagent でよい（spawn overhead に見合わない）。

### 系統B: 当日ノートの `_id` / `_rev` 解決

「今日の日付」は**セッションに与えられた日付を唯一の基準にする**（`date` を引き直さない。日付をまたいで再開したとき、両者が食い違うと分岐が揺れる）。

```
1. ~/.cache/inbox-capture/today-note-id を読む
2a. キャッシュあり: read-note を実行
    - 「ノートが無い」と確定した失敗 (404 / not_found / 削除済み) → キャッシュを破棄し 2b へ
    - 呼び出し自体が完了しなかった失敗 (タイムアウト / 認証エラー / MCP 接続断)
      → キャッシュは破棄しない（ノートが消えた証拠ではない）。1回だけ再試行し、
        それでも駄目なら中断してユーザーに報告する
    - 成功 → title が `inbox <今日の日付>` と一致するか必ず検証する
        - 一致   → _id, _rev, 本文を確定して終了 (MCP 1回)
        - 不一致 → 日付をまたいで前日以前を指している。キャッシュを破棄し 2b へ
2b. search-notes で `book:inbox title:"inbox YYYY-MM-DD"` を検索
    - ヒット → _id をキャッシュに保存し、read-note で本文と _rev を取得 (MCP 2回)
    - ミス   → 新規作成扱い。list-notebooks で bookId を解決し、Phase 2 で create-note (MCP 1回)
```

**`read-note` の成功は「今日のノートである」ことを保証しない**（ノートは削除されず残り続けるため）。title 検証を省略しない。

## Phase 2（1回のみ）: 一括書き込み

Phase 1 で揃った全セクションをまとめて当日ノートに書く。**MCP 呼び出しは 1 回だけ**。

- 新規作成: `create-note`。**`status: "active"` を必ず指定する**（省略すると `none` になり Inkdrop に表示されない）。作成された `_id` を `~/.cache/inbox-capture/today-note-id` に保存する。
  - **キャッシュ書き込みは sandbox 内では失敗する**（`~/.cache` は既定の書き込み許可範囲外で `Operation not permitted`）。`dangerouslyDisableSandbox` を付けて実行する。恒久対策は settings.json の `sandbox.filesystem.allowWrite` に `~/.cache/inbox-capture` を追加すること。
- 追記: `update-note`。引数は `_id` と `_rev`（`noteId` ではない）で、`read-note` の結果から取る。**`read-note` で得た既存本文を絶対に消さず、末尾にセクションを追加するだけにする。**
  - **既存本文が大きいときは MCP ツールの `body` 引数を使わない**: `update-note` は body 全文を引数に取るため、既存本文を一度 main の文脈へ載せることになる。当日ノートは 20 件ほどで 60,000 字を超え（実測: `read-note` がトークン上限を超えてファイルへ退避された）、これを丸ごと文脈に置くと以降の作業が潰れる。この規模では**全 CLI 共通で** `jq --rawfile` + stdio 経路（後述「1Password 認証爆発の防止」）を使い、既存本文をファイル上で連結して流す——文脈に載せるのは追記する新セクションだけにする。
  - **退避された `read-note` の結果から `_rev` / `title` を拾うときは pretty-print を前提にする**: 退避 JSON は整形済みなので `"_rev":"` では引っかからない（`"_rev": "` と空白が入る）。`grep -o -E '"(_rev|title)": "[^"]*"'` の形で取る。
- **`bookId` は inbox ノートブックの実 `_id`**（例 `book:51GBqxKj`）。`^(book:|trash$)` パターン必須で、表示名 `inbox` や `book:inbox` では通らない。`list-notebooks` の `name == "inbox"` から引く。
  - 混同注意: `search-notes` の `book:inbox` は**表示名フィルタ**なのでそのまま使える。実 `_id` を要求するのは `create-note` / `update-note` の `bookId` 引数だけ。
- **タグは付けない**（週次レビューで「育てる」判定して昇格したときだけ付ける）。

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

- **要約は散文のみ。Mermaid 図・表は使わない**（`note-taking` skill は Inkdrop ノート一般に「順序・フロー・アーキテクチャの話なら図を使え」と勧めるが、**日次要約ではこの skill が優先する**。理由: 5〜10 行という分量方針と衝突する。図解は週次で「育てる」判定を受けて個別ノート化するときに行う）。
- **ノート間リンクは `[タイトル](inkdrop://note/<id>)`**（`note:` プレフィックスを落とす）。Inkdrop に `[[wiki-link]]` 記法は無い。記法の詳細は `note-taking` skill。

要約の粒度は 5〜10 行。「何が書かれているか」+「なぜ気になるか」の両方を伝える。ただし**長大な記事も要約だけで完結する量**にとどめる（深読みは週次で判定する）。

`### メモ` は**気づきや関連メモを自由に書いてよい欄**。空欄でも構わないが、書く材料があれば書く（例: 取得上の注記——部分取得だった / playwright で取り直した、既存ノートや他記事との関連、後で確かめたい点）。人間も後から同じ欄に追記するので、**追記時に既存のメモを消さない**。

## 読了判定

日次の時点で読むかどうかを決める。**「即読了」と「要約で十分」はここで完了**し、週次レビューで再判定しない。「後で読む」だけが週次の対象になる。

**関心軸を先に判定する**（分量軸と関心軸を同時に見ると、短くて関心の中心にある記事がどちらにも当てはまってしまう）:

1. **深読みして知識化したいか？** → Yes なら**分量に関わらず「後で読む」**
   - 「誰の関心か」の参照元は、作業中リポジトリの `CLAUDE.md` と `.claude/plans/` の進行中タスク、および既存 inbox ノートで「後で読む」が付いた記事の傾向。判断はあくまで実行者の推定なので、**迷ったら理由を `### メモ` に1行残す**（週次で人間が覆せる）。
2. No のときだけ分量で振る → その場で読み切れた量なら「即読了」、そうでなければ「要約で十分」

| 判定 | 目安 | 週次での扱い |
|---|---|---|
| 即読了 | 取得した本文が5,000字以下で、その場で読み切れた | 対象外（完了） |
| 要約で十分 | 取得した本文が5,000字超、関心の周辺、概観で足りそう | 対象外（完了） |
| 後で読む | 関心の中心、深読みで知識化したい | weekly-review で 育てる/捨てる 判定 |

字数の目安は**取得した本文**（`NNN.md`）の量で測る。原文の長さは手元にないので基準にしない。**測るときは `wc -m`（文字数）を使い、`wc -c`（バイト数）と混同しない**——日本語記事では実測 1.7〜2.2 倍ずれ、判定が1段階狂う。**PDF は `NNN.pdf` しか出ないので字数では測れない**。ページ数を代理指標にする（目安: 10 ページ以下なら「即読了」相当の分量）。

非記事ページ（EC の商品一覧・検索結果・ダッシュボード等）も Chrome のタブには普通に混ざる。この場合、要約対象は本文ではなく**列挙の要点**（件数・分類・価格帯・在庫や締切）にし、分量軸は「一覧を見て判断が済むか」で読む。

## タイムアウト

- **fetch**: 10 秒（`fetch-batch.sh` が `ax -m 10` で強制。`gh` にはタイムアウト指定がないので gh 自身の挙動に委ねる）。リトライしない（上記「取得失敗の扱い」）。
- **MCP（Stateless = Antigravity）**: 60 秒（`op run` 認証 + `npx` 起動を含む）。失敗時は 1 回だけリトライしてよい。
- **MCP（Persistent = Claude / Codex）**: 30 秒。失敗時は 1 回だけリトライしてよい。

## ⚠️ 1Password 認証爆発の防止

- **原因を直さずにリトライしない**: `op run` 経由のコマンドが失敗したとき（環境変数パスのミス、JSON フォーマットエラー、コマンドインジェクション警告など）、修正せずに再実行を繰り返すと、ユーザーに大量の 1Password 認証ポップアップが出る。
- **JSON は `jq` で組み立てる**: 改行やクォートを含む長い Markdown を MCP へ送るとき、シェルの文字列補間（`echo '{"body": "'$BODY'"}'`）や Python 等での迂回をしてはならない。**必ず `jq -nc --rawfile body <ファイル>` でエンコードと 1 行化を行う**。
  - 例: `jq -nc --rawfile body ./tmp.md '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create-note","arguments":{"body":$body,"title":"inbox ...","bookId":"book:...","status":"active"}}}' | op run --env-file=~/dotfiles/coding-agents/inkdrop.op.env -- npx --prefer-offline -y @inkdropapp/mcp-server`
- **テストノートを作らない**: 認証やペイロードの調査のために本番 DB へ空ノート（`{"body": "test"}` 等）を作ってはならない。作ってしまったら直ちに `update-note` で `status: "dropped"` にする。調査は `op run` を通さないローカルの `jq` 出力確認にとどめる。
