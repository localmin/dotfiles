---
name: tmux-runner
description: >-
  Run interactive CLIs and long-running/daemon commands inside a tmux session
  instead of a one-shot Bash call — start detached, drive prompts with
  send-keys, observe with capture-pane, log to a file, and hand a live session
  to the human via attach. Use this whenever a command is INTERACTIVE (waits for
  keyboard input: prompts, REPLs, scaffolders like `create-next-app` / `npm init`
  / `prisma init`, login or auth flows, `gh auth login`, anything that asks
  questions), OR LONG-RUNNING / PERSISTENT (dev server, `watch` mode, test suite,
  build, log tail) that should survive across turns, be observed while running,
  or be shared with the human or another CLI. Reach for this even if the user
  never says "tmux": if you would otherwise answer "this command is interactive,
  please run it yourself" or block the turn waiting on a server, use this skill
  instead.
---

# tmux-runner

普通の Bash 実行は「一発で投げて、終わったら結果が返る」モデル。これは **対話型コマンド**（質問→入力→質問…の往復）とも、**常駐コマンド**（終わらずに動き続ける）とも噛み合わない。tmux はコマンド専用の「つけっぱなしの端末」を立て、いつでも `capture-pane`（画面を読む）と `send-keys`（キーを打つ）で何度でも往復できるようにする。これにより、対話 CLI を人間の代わりに駆動でき、常駐プロセスを観測しながらターンを跨いで生かせる。

## いつ使うか

- **対話型 CLI**: 入力待ちで止まるもの。`npx create-next-app`、`npm init`、`prisma init`、`gh auth login`、各種ログイン、REPL、`git rebase -i` 的なもの。「対話型だから不可」と諦めず tmux で駆動する。
- **長時間 / 常駐コマンド**: dev server、`watch`、テストスイート、ビルド、ログ追従。ターンを跨いで生かしたい・途中経過を観測したい・人間や別 CLI と共有したい。
- **使わない**: 数秒で終わる fire-and-forget は通常の Bash（必要なら Claude Code の `run_in_background`）で十分。tmux は上記の利点（跨いで生存／観測／共有／対話）が要るときだけ。

## 対話型コマンドのコアループ（最重要）

`capture-pane → 判断 → send-keys → capture-pane` を繰り返す。**決め打ちで連続入力しない**。

```bash
tmux new-session -d -s scaffold 'npx create-next-app@latest myapp'
tmux capture-pane -t scaffold -p | tail -n 25      # 今どのプロンプト？
tmux send-keys -t scaffold 'myapp' Enter           # 質問に答える
tmux capture-pane -t scaffold -p | tail -n 25      # 反映と次のプロンプトを確認
tmux send-keys -t scaffold Enter                   # 次の答え（default など）
# …最後まで「読む→打つ」を繰り返す
```

**タイミングの注意（なぜ確認駆動か）**: `capture-pane` は画面の**スナップショット**。起動直後やコマンド処理中は、次のプロンプトがまだ描画されていないことがある。空振りしたら一拍おいて取り直す:

```bash
sleep 1; tmux capture-pane -t scaffold -p | tail -n 25
```

プロンプトが出ていないのに `send-keys` すると入力が無視されたり別の場所に入る。**必ず capture で確認してから送る**。

特殊キーはキー名で送る: `Enter` / `C-c`（Ctrl-C）/ `Up` `Down`（メニュー選択）/ `Space`（トグル）/ `Tab`（補完）。例: メニューを2つ下げて確定 → `tmux send-keys -t s Down Down Enter`。

## 長時間 / 常駐コマンド

detached で起動し、起動確認だけして次へ進む（ターンをブロックしない）。

```bash
mkdir -p ~/.cache/tmux-logs
tmux new-session -d -s app-dev "bash -lc 'npm run dev 2>&1 | tee ~/.cache/tmux-logs/app-dev.log'"
sleep 2; tmux capture-pane -t app-dev -p | tail -n 15   # "Local: http://localhost:3000" を確認して報告
```

監視は `attach` ではなく `capture-pane`（または `tail -f` でログファイル）。ユーザーには `tmux attach -t app-dev` で覗ける旨を伝える。

## ログ

セッション終了後も検証できるよう、ログはファイルに残す。

- 起動時に流す: `... 2>&1 | tee ~/.cache/tmux-logs/<name>.log`
- 起動後に足す: `tmux pipe-pane -t <name> -o 'cat >> ~/.cache/tmux-logs/<name>.log'`

`~/.cache/tmux-logs/` は事前に `mkdir -p` しておく。

## セッション命名

用途が一目で分かる名前にする: `<repo>-dev` / `<repo>-test` / `agent-<task>` / `scaffold`。匿名の番号セッションを乱立させない。`tmux ls` で人間や別 CLI が識別・引き継ぎできることが狙い。

## 人間への引き継ぎ

自分が答えられない入力（パスワード・2FA・captcha・最終判断）に当たったら、プロセスを tmux で生かしたまま渡す。**自分が `attach` して固まらない**。

> このあとパスワード入力が必要です。`tmux attach -t <name>` で入って続けてください。終わったら教えてください。

## CLI / エージェント跨ぎ

tmux セッションは CLI を跨いで見える。別 CLI（Antigravity / Codex）や別エージェントが起動したセッションも `tmux ls` → `tmux capture-pane -t <name> -p` で監視・引き継ぎできる。逆に自分が起動したものも共有される。

## 後始末

用が済んだセッションは閉じる: `tmux kill-session -t <name>`。常駐サーバなど意図的に残すものは、その旨をユーザーに伝えてから残す。

## アンチパターン

- 対話型 CLI を無理に非対話で叩いて詰まる（パイプで答えを流し込む等）→ tmux + `send-keys` で見ながら答える。
- `capture-pane` で確認せず「動いているはず」で次へ進む → 必ずスナップショットで状態を見る。
- `attach` したままターンをブロックする → 監視は `capture-pane`、`attach` は人間に委ねる。
- ログを残さずセッションを閉じ、後から検証不能にする → 常に `tee` / `pipe-pane`。
- エージェント固有の不透明なバックグラウンド機構に頼り、`tmux ls` で一覧できない状態にする。

## クイックリファレンス

| やること | コマンド |
|---|---|
| 起動（detached） | `tmux new-session -d -s <name> '<cmd>'` |
| 一覧 | `tmux ls` |
| 画面を読む | `tmux capture-pane -t <name> -p \| tail -n 80` |
| キーを送る | `tmux send-keys -t <name> '<text>' Enter` |
| 特殊キー | `tmux send-keys -t <name> C-c` / `Down` / `Space` |
| ログ追従 | `tail -f ~/.cache/tmux-logs/<name>.log` |
| 人間に渡す | 案内: `tmux attach -t <name>` |
| 閉じる | `tmux kill-session -t <name>` |
