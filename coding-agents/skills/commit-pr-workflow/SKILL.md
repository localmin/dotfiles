---
name: commit-pr-workflow
description: コミット / push / PR 作成を頼まれたときに使う一連の手順。粒度整理・push 前レビューゲート・repo 運用の判定（直コミット vs branch+PR）・commit message / PR 本文の書式を、この環境の規約どおりに実行する。commit と push は別フェーズで、頼まれた分だけ実行して止まる。
---

# commit / push / PR ワークフロー

コミット〜push〜PR を、この環境の既存規約どおりの順序で実行するための手順書。
**規約の実体は CLAUDE.md にある**——ここでは再掲せず参照し、「一連の流れ」と
「CLAUDE.md に無い書式（trailer / PR 本文 / branch-first）」だけを定める。

## 大原則

- **commit も push もユーザーが頼んだときだけ**行う。commit の後に**自動で push しない**。
- 頼まれたフェーズだけ実行して**止まる**。「commit して」なら commit まで、「push して」で push。

## 前提（詳細は CLAUDE.md、ここは1行参照）

- 粒度は論理単位に整える / commit 直前に `git status` で index 全体を確認する /
  `git commit` は sandbox 外で実行する / GitHub 参照は `gh` 優先 / commit message は英語。
  いずれも CLAUDE.md の該当ルールに従う（本 skill では繰り返さない）。

## 最初にやる: repo 運用の判定

その repo が **直コミット運用**か **branch + PR 運用**かを判定する。分岐材料:
repo の `CLAUDE.md` / `README` / `CONTRIBUTING` / 既存 git 履歴（merge commit や PR の有無）。
不明なら推測せず聞く。

- 例: この dotfiles repo は「master 直コミット / 直 push（PR なし）」。

## フェーズ1: commit（「commit して」で実行し、ここで止まる）

1. `git log` / `git status` を見て**粒度を整える**。多目的な変更は論理単位に分割、
   無意味な細切れは squash。共有ファイルに複数の関心が混在する場合は hunk 単位で分けて
   別コミットにする。
2. commit 直前に **`git status` で index 全体を確認**（path を絞った add でも、
   既に stage 済みの無関係な変更が混ざっていないか見る）。
3. **commit する（sandbox 外）**。message 書式は下記「commit message」。
4. **push はしない**。「N コミット作成、push は未実施」と報告して終わる。

## フェーズ2: push（「push して」で実行）

5. **push 前ゲート**: `/code-review` と `/security-review` を通し findings に対処する。
   - Claude Code: PreToolUse hook（`pre-push-review-gate.sh`）が未レビューの push をブロックし
     手順を提示する。承認後 `git rev-parse HEAD > <gitdir>/review-ok` で HEAD を記録して再 push。
   - 他 CLI: hook が無いので手動で両レビューを実施する。
6. **push**:
   - **直コミット運用**: default ブランチのまま `git push`。
   - **PR 運用**: default ブランチにいるなら**先に作業ブランチを切る（branch-first）**。
     `git push -u origin <branch>` → `gh pr create`（PR 本文書式は下記）。PR は WebFetch でなく
     `gh` で作る。
7. **push 後**: 試行錯誤・ユーザー訂正・非自明な修正があったセッションなら
   `retrospective-codify` の実行を検討（CLAUDE.md 参照）。

## commit message

- 英語。件名は論理変更を端的に（命令形）。本文は必要なら why を数行。
- trailer は **`Co-Authored-By` の1行のみ**。起動中の CLI の AI を co-author にする
  （固定しない）。例:
  - Claude Code: `Co-Authored-By: Claude <noreply@anthropic.com>`
  - Codex: `Co-Authored-By: GPT <noreply@openai.com>` 相当
  - Antigravity: `Co-Authored-By: Gemini <noreply@google.com>` 相当
- セッション URL 等の trailer は付けない（private・非永続・cross-CLI で破綻するため）。

## PR 本文（PR 運用 repo のみ）

- 冒頭に変更概要、続けて test plan（どう検証したか）。
- 末尾に生成元を1行（起動 CLI に合わせる。例: Claude Code なら
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`）。
- 本文は英語（CLAUDE.md 言語ルール）。
