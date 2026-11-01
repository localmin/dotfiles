---
name: eprint-digest
description: IACR ePrint の 7 カテゴリ RSS から前回以降の新着論文を取得し、全件を日本語に訳して今週の流行・ピックアップ論文の概要・用語解説をまとめ、Inkdrop の inbox に週次ノート（ePrint digest YYYY-Www）として書く（同じ週の再実行は追記）。「ePrint のダイジェスト」「今週の ePrint」「暗号論文の週次まとめ」を頼まれたら使う。週次運用想定。
---

# eprint-digest

IACR ePrint の新着論文を週 1 回まとめ、Inkdrop の inbox ノートブックに **`ePrint digest YYYY-Www`** ノートとして書く。狙いは 3 つ: 英語タイトルを読まずに済ませる / PQC の動きを抜き出す / 研究全般の流行をつかむ。入力は不要。

ノートは **今週の流行 / ピックアップ（5〜8 本、各 3〜5 行の概要）/ 用語解説** の 3 欄。全件一覧は載せない（読み手が困るだけ、とユーザー判断 2026-11-01）。ただし流行は全件から判断するので、全件の翻訳がそろっていることは `render-digest.py` が内部で確かめる。

取得・選別・本文の組み立ては決定的なスクリプトで行い、LLM がやるのは **1 件ごとの翻訳と PQC 判定（subagent）**、**流行の所感とピックアップの選定（main）**、**ピックアップの概要と用語解説（subagent）** だけ。件数・網羅確認・並べ替えのように、論文を落とす余地のある作業は LLM にさせない。

Inkdrop MCP の呼び出し方針（CLI ごとの起動、1Password、`jq --rawfile` 経路、テストノートを作らない）は **inbox-capture skill の「前提」と「1Password 認証爆発の防止」に従う**。本 skill はそれを前提に ePrint 固有の部分だけを書く。

スクリプトは `~/dotfiles/coding-agents/skills/eprint-digest/scripts/`（以下 `S/`）。作業ディレクトリ `W` は**実行ごとに新しく作る**: `mktemp -d "<scratchpad か $TMPDIR>/eprint-digest.XXXXXX"`。既存のディレクトリを使い回さない（前回の `batch-*` が `split` と `W/batch-*.out.jsonl` の glob に混ざり、Phase 4 が `unknown id` で落ち続ける）。

## inbox に置くための制約（破ると他 skill が誤動作する）

- **タイトルに `inbox YYYY-MM` の形を含めない**。inbox-capture は `title:"inbox YYYY-MM-DD"`、weekly-review は `book:inbox title:"inbox YYYY-MM"` で日次ノートを探すので、形が合うと拾われる（`render-digest.py` が拒否する）。
- **本文に `読了判定:` を書かない**。weekly-review はこの行のあるセクションを処理対象にする（`render-digest.py` が拒否する）。深読みしたい論文は Chrome ウィンドウに開いて inbox-capture に流す経路で日次ノートに入れる。
- **タグを付けない**。inbox のノートはタグなしの運用で、notebooklm-judge の集計を汚さない。
- 対象は ePrint だけ。ブログは Inoreader で読む運用（含めない）。

## Phase 0: タイトルを決める

「今日」は**セッションに与えられた日付を唯一の基準にする**（`date` で引き直さない）。週は実行日の ISO 週で、年も ISO 週年を使う（年末年始で暦年とずれる）:

`date -j -f %Y-%m-%d <今日> +'ePrint digest %G-W%V'`

## Phase 1（並列）: 取得・選別 ∥ 同週ノートの解決

### 系統A: 取得 → 新着の選別

1. `S/fetch-feeds.sh -o W/feeds` — 7 カテゴリを並列取得（`eprint.iacr.org` への通信が要る）。**exit 1 なら中断して報告**（失敗カテゴリは `W/feeds/<CAT>.err` に ax の出力が残る）。1 カテゴリでも欠けたまま進むと、位置だけ進んでそのカテゴリの論文が永久に落ちる。
2. `S/select-new.py select --feeds-dir W/feeds -o W/new.jsonl` — 前回位置より新しい論文を JSONL に出す。標準出力は `mode / total / count_<CAT> / max_id / warn_gap / out` の key=value だけで、**要旨は出ない**。

| 出力 | 対応 |
|---|---|
| exit 3 | フィードか状態ファイルが読めない。中断して stderr を報告（状態ファイルを消して初回扱いにしない＝既読分を二重に処理する） |
| `total=0` | 新着なし。ノートも状態も触らず終了 |
| `mode=initial` | 状態ファイルが無い初回。直近 7 日分を処理したと報告する |
| `warn_gap` が空でない | そのカテゴリのフィード 100 件が全部新着＝それより古い未処理分が落ちている可能性。報告に必ず書く |

- **`W/new.jsonl` を main で Read しない**（週約 95 件で約 4 万 token の要旨。推測）。中身を扱うのは Phase 2 の subagent だけ。
- 前回位置は `~/.cache/eprint-digest/state.json`（`EPRINT_DIGEST_STATE` で変更可）。select は状態を**書かない**。書くのは Phase 5。

### 系統B: 同週ノートの `_id` / `_rev` 解決

`search-notes` で `book:inbox title:"<Phase 0 のタイトル>"` を検索する。

- **ヒット（同じ週の 2 回目）**: 既存ノートに追記する。`~/dotfiles/coding-agents/skills/inbox-capture/scripts/note-head.sh -o W/head --expect-title "<タイトル>" <note:ID>` で `id / rev / body_path` を得る（本文を文脈に載せない。exit code の意味は inbox-capture の系統B 表と同じ）。
- **ミス**: 新規作成。`list-notebooks` の `name == "inbox"` から実 `_id`（`book:...`）を引く。

## Phase 2: 1 件ごとの処理（subagent に隔離）

1. 20 件ずつに分ける: `split -l 20 W/new.jsonl W/batch-`
2. バッチごとに `general-purpose` subagent を 1 つずつ、**同一ブロックで並列に** dispatch する。プロンプトは下記テンプレート。
3. 戻り値は件数だけ。結果ファイルの検証は Phase 4 の `render-digest.py` がやる（欠け・重複・不正な値は exit 3 で id を名指しする）。exit 3 はエラーの種類で直し方が違う（1 回に 1 件しか名指ししないので、直したら再実行して次を見る）:
   - **`no result for: <id>, …`（欠け）**: 名指しされた id だけを `jq -c 'select(.id == "...")'` で抜いた新バッチにして subagent を 1 つ追加で投げ、`W/batch-fix.out.jsonl` に書かせる。
   - **それ以外（値の不正・`duplicate result`・`unknown id`・壊れた JSON 行 `<file> line N`）**: エラーが出たバッチを丸ごと投げ直し、**同じ出力ファイルを上書き**させる。壊れた行は元ファイルに残るので、fix ファイルを足すと `duplicate result` で再び落ちる。

subagent プロンプト（`<...>` を埋める）:

```
ISOLATED-EXECUTOR: あなたは隔離済みの実行者です。再委譲せず inline で実行してください。

入力: <W/batch-xx>（JSONL。1 行 1 論文: id, category, title, link, published, authors, abstract）
出力: <W/batch-xx.out.jsonl> に 1 行 1 論文で {"id", "title_ja", "summary_ja", "pqc"} を書く。
入力の全 id をちょうど 1 回ずつ出す。JSON は jq か Write で書き、壊れた行を作らない。

- title_ja: 原題の日本語訳。意訳してよいが、方式名・プリミティブ名（ML-KEM, FHE, SNARK 等）は英語のまま残す。
- summary_ja: 要旨から「何をして、何が分かった / 速くなった」を 1 文（60〜100 字目安）。改行しない。
- pqc: 耐量子暗号に関係すれば true。対象は PQC 方式（格子・符号・ハッシュ・同種写像・多変数）と
  その標準（ML-KEM, ML-DSA, SLH-DSA, FN-DSA, HQC 等）の設計・実装・攻撃・移行・ハイブリッド構成、
  量子攻撃者を想定した安全性解析。単に「量子」に触れるだけ（量子鍵配送の物理実装など）は false。
  迷ったら true（PQC 件数の集計とピックアップの優先度に使うので、取りこぼす方が困る）。
- 「読了判定:」という文字列を書かない。

返答は「<出力パス>: N 件」の 1 行だけ。要旨や訳文を返答に含めない。
```

## Phase 3: 今週の流行とピックアップの選定

`jq -r '[.id, (if .pqc then "P" else "-" end), .title_ja, .summary_ja] | @tsv' W/batch-*.out.jsonl` で訳と 1 行要約だけを読み（英語の要旨は読まない）、`select` が出したカテゴリ別件数と合わせて次の 2 つを書く。

**`W/trends.md`**（箇条書き）:

- 3〜6 項目。各項目は「話題（N 件）: id, id, ...」の形で、根拠の論文 id を必ず付ける。
- 主題ラベルは付けない運用なので、話題のまとめ方は所感でよい。**週をまたいだ比較はしない**（比べる単位が無い）。
- カテゴリ別件数と PQC 件数の行は `render-digest.py` が付ける。自分で書かない。

**`W/picks.txt`**（1 行 1 id、表示したい順）: 5〜8 本（新着が少ない週はそれ以下でよい。上限 8 は `render-digest.py` が強制）。

- PQC 関連（`P`）を優先する。追いたい動向の 1 つ目が PQC 移行のため。
- 流行欄の各話題から代表を 1 本ずつ。
- 単独でも目立つ結果を拾う: 実用的な攻撃、標準や実製品に影響するもの、桁の違う性能改善やリソース見積り。

## Phase 3b: ピックアップの概要と用語解説（subagent に隔離）

概要は要旨を読まないと書けないので、ここも subagent に任せる（main に要旨を載せない）。

1. 選んだ論文を表示順に抜く: `jq -c -s --rawfile ids W/picks.txt '. as $all | $ids | split("\n")[] | gsub("^\\s+|\\s+$"; "") | select(. != "") as $i | $all[] | select(.id == $i)' W/new.jsonl > W/picks.in.jsonl`
   - 抜けた件数を確かめる: `grep -c '[^[:space:]]' W/picks.txt` と `wc -l < W/picks.in.jsonl` が一致すること。合わなければ picks.txt の id の打ち間違いで、そのまま進むとピックアップが黙って減る（`render-digest.py` は減ったことを検出できない）。
2. `general-purpose` subagent を 1 つ dispatch する（プロンプトは下記）。
3. 検証は Phase 4 の `render-digest.py` がやる（未知の id・重複・空・見出し混入・`読了判定:` は exit 3）。exit 3 なら同じ subagent に出力ファイルの上書きをやり直させる。

```
ISOLATED-EXECUTOR: あなたは隔離済みの実行者です。再委譲せず inline で実行してください。

入力:
- <W/picks.in.jsonl>: ピックアップする論文（id, category, title, link, authors, abstract）。この順で扱う。
- <W/batch-*.out.jsonl>: 全件の日本語タイトル title_ja（ピックアップの見出しになる）。
- <W/trends.md>: ノートの「今週の流行」欄。

出力 1: <W/picks.out.jsonl> に入力と同じ順で 1 行 1 論文 {"id", "overview_ja"}。
  overview_ja は 3〜5 行（行は \n で区切る）。「何が問題で / 何をして / 何が分かった・どれだけ良くなったか /
  なぜ重要か」が分かるように書く。数値は要旨にあるものだけ使う。見出し（# で始まる行）は書かない。
出力 2: <W/glossary.jsonl> に 1 行 1 語 {"term", "desc"}（8〜15 語目安）。
  対象は、trends.md・ピックアップの title_ja・overview_ja に出てくる専門用語。
  読者は暗号の基礎（公開鍵・署名・ハッシュ・格子暗号・LWE・サイドチャネル攻撃という概念）は知っている前提で、
  それらは解説しない。方式名（SMAUG-T 等）・攻撃手法（herding、単一トレース攻撃 等）・証明系（IOP、SNARK 等）・
  数学用語・量子計算の用語（cat qubit 等）を 1〜2 文で説明する。ノートに出てくる順に並べる。
JSON は jq か Write で書き、壊れた行を作らない。「読了判定:」という文字列を書かない。

返答は「picks: N 件 / glossary: M 語」の 1 行だけ。
```

## Phase 4: 本文の組み立てと書き込み（MCP 1 回）

- 新規: `S/render-digest.py --items W/new.jsonl --results W/batch-*.out.jsonl --trends W/trends.md --picks W/picks.out.jsonl --glossary W/glossary.jsonl --title "<タイトル>" -o W/body.md`
- 追記: 同じコマンドに `--append-date <今日>` を付けて `-o W/add.md`、その後 `cat <body_path> W/add.md > W/body.md`（既存本文は文脈に載せない）。追記分は `## 追加分（<今日> 実行）` の下に 1 段下げで入る。

書き込みは inbox-capture と同じ **`jq -nc --rawfile body W/body.md` + `op run ... @inkdropapp/mcp-server` の stdio 経路**（sandbox 外で実行）:

- 新規: `create-note`。引数は `body` / `title` / `bookId`（実 `_id`）/ **`status: "active"`**（省略すると `none` になり表示されない）。
- 追記: `update-note`。引数は `_id` と `_rev`（`note-head.sh` の `id` / `rev`）と `body`。

応答に `error` が無く、`_id` が返ったことを確かめてから Phase 5 へ進む。

## Phase 5: 前回位置を進める

`S/select-new.py commit --max-id <Phase 1 の max_id>`

- **ノートの書き込みが成功した後にだけ実行する**。先に進めると、書き込みに失敗した週の論文が二度と選ばれない。
- 位置は後ろへは戻らない（古い id を渡すと `unchanged`）。番号は (年, 番号) の組で比べるので `2027/0001` は `2026/2600` より新しい。
- `~/.cache` への書き込みは settings.json の `sandbox.filesystem.allowWrite` に `~/.cache/eprint-digest` を入れてあるので sandbox 内で通る。`Operation not permitted` なら設定漏れを疑う。

## 報告

ノートのタイトルとリンク（`inkdrop://note/<id>`、`note:` を落とす）、新規 / 追記の別、総件数、PQC 件数、ピックアップ本数、`mode=initial` だったか、`warn_gap` のカテゴリ、Phase 2 で取り直した id を短く返す。

## 既知の限界

- 位置は「最大番号」1 つで持つ。番号の小さい論文が後から公開されると拾えない（2026-10-26 時点、実フィード 100 件で番号と公開日の逆転は 0 件）。
- 各カテゴリのフィードは最新 100 件まで。4 週以上空けると取りこぼしうる（`warn_gap` が出る）。

## テスト

オフラインで動く回帰テスト（ネットワーク・認証なし。`TMPDIR` が書けない環境は `TEST_TMPDIR=<書ける場所>`）: `S/test-fetch-feeds.sh`（ax を stub）/ `S/test-select-new.sh`（`fixtures/week`, `fixtures/rollover`）/ `S/test-render-digest.sh`（`fixtures/render` の golden）。
