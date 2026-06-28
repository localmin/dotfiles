# tmux 運用ルール（AI エージェント向け）

CLAUDE.md の「開発ポリシー」索引から必要時に読み込む詳細 doc（on-demand Read）。長時間実行コマンドと対話型 CLI を、**エージェント非依存で「独立・観測可能・共有可能」**に扱うための運用。参考: https://zenn.dev/nasubikun/articles/tmux-for-ai-agents

## なぜ tmux か

- **プロセス独立**: 親プロセス（エージェントのターン）から分離され、ターン終了・Ctrl-C・セッション終了後も生存する。
- **観測可能**: `tmux ls` で一覧、`capture-pane` で現在の出力をスナップショット取得できる。
- **共有可能**: ある CLI（Claude）が起動したセッションを別 CLI（Antigravity / Codex）や人間が参照・監視できる。
- **対話対応**: `send-keys` でキー入力を自動化でき、対話型 CLI を非対話的に諦めずに駆動できる。

Claude Code の `run_in_background` は手軽で、**ターン内で完結する短い非同期処理**には十分。次のいずれかが要るときに tmux を使う: ①ターン/セッションを跨いで生かしたい ②別 CLI・人間から見たい・引き継ぎたい ③対話入力が要る。

## いつ tmux を使うか

- **長時間 / 常駐コマンド**: dev server、`watch`、テストスイート、ビルド、ログ追従など。途中経過を観測したい・跨いで生かしたい。
- **対話型 CLI**: `npx create-next-app`、各種 prompt、REPL、ログインフローなど。「対話型だから実行不可」と返さず、tmux + `send-keys` で応答を送る。
- **使わない**: 数秒で終わる fire-and-forget は通常の Bash（必要なら `run_in_background`）。tmux は上記の利点が要るときだけ。

## 基本コマンド（エージェントが叩く）

複数行の手順は `~/dotfiles/coding-agents/skills/` ではなくここに集約（policy なので inline 可）。

- 起動（detached）: `tmux new-session -d -s <name> '<command>'`
- ログもファイルに残す（セッション終了後も検証可能に）:
  - `mkdir -p ~/.cache/tmux-logs && tmux new-session -d -s <name> "bash -lc '<command> 2>&1 | tee ~/.cache/tmux-logs/<name>.log'"`
  - または起動後に `tmux pipe-pane -t <name> -o 'cat >> ~/.cache/tmux-logs/<name>.log'`
- 一覧: `tmux ls`
- 状態を読む（スナップショット、attach しない）: `tmux capture-pane -t <name> -p | tail -n 80`
- 対話入力を送る: `tmux send-keys -t <name> 'y' Enter`（特殊キーは `Enter` / `C-c` / `Down` 等のキー名で）
- 人間に渡す: そのまま attach しっぱなしにせず、「`tmux attach -t <name>` で入れます」と案内する
- 後始末: 用が済んだら `tmux kill-session -t <name>`

## 命名規約

- セッション名は**用途が一目で分かる**ものにする: `<repo>-dev` / `<repo>-test` / `agent-<task>`。他 CLI・人間が `tmux ls` で識別・引き継ぎできるようにする。匿名の番号セッションを乱立させない。

## アンチパターン

- エージェント固有の不透明なバックグラウンド機構に頼り、後から状態を追えなくする。
- 対話型 CLI を無理に非対話で叩いて詰まる → tmux + `send-keys`。
- `capture-pane` で確認せず「動いているはず」と決め打ちする → 必ずスナップショットで確認してから次へ進む。
- `attach` したままターンをブロックする → 監視は `capture-pane`、`attach` は人間に委ねる。
- ログをファイルに残さずセッションを閉じ、後から検証できなくする。

## 各 CLI 共通

このルールは Claude / Antigravity / Codex 共通（policy doc は CLAUDE.md から絶対パス参照のため全 CLI で同一ファイルを読む）。tmux セッションは CLI を跨いで参照できるので、ある CLI が起動したテストを別 CLI が `capture-pane` で監視する、といった分業が可能。
