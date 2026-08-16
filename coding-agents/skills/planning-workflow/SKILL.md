---
name: planning-workflow
description: 機能の計画・実装に入るとき、複数ステップの作業を始めるとき、または中断した作業を再開するときに使う運用規約。plan mode の合意を .claude/plans/ の永続 doc に残す手順、INDEX.md / WIP.md の運用、セッション越え・compaction 後の継続方法を定める。計画・再開・途中状態の保存が関わる場面では必ず参照する。
---

# 計画ワークフロー（plan mode → 永続 doc）

## 目的

セッションをまたいだり compaction が走っても、plan mode で詰めた要件・設計議論を失わず再参照できるようにする。議論を構造化 doc としてプロジェクト内に永続化する。

## 手順

1. **plan mode で要件を詰める**。非自明な実装・複数の妥当な方針・複数ファイルにまたがる変更は、まず plan mode に入って合意形成する。
2. **合意できたら `plan-doc` skill で構造化 doc を生成**する。skill が雛形を作るので、議論内容で各セクションを埋める。
3. **実装中も doc を更新**する。タスクの進捗・決定の変更は該当 doc に反映し、議論の現状を doc 側に持たせる（会話コンテキストに依存させない）。

## 生成 doc に含めるセクション

セクション構成は `plan-doc` skill の `template.md` が正（Goals / Spec / 前提と検証状況 / 設計 / Task 分割 / 実装の進め方 / 動作確認）。ここでは列挙を持たず template を参照する。

## `.claude/plans/` レイアウト規約

プロジェクトルート相対で、per-project に分離する:

```
<project-root>/.claude/plans/
├── INDEX.md                     # 索引。1 plan = 1 行（パス + フック）
└── <YYYY-MM-DD>-<slug>.md       # 個別 plan doc
```

- **INDEX.md が入口**。作業開始時はまず INDEX.md を読み、関連するエントリだけ詳細 doc を Read する（lazy-read 規律 — 全部は読まない）。
- 1 plan につき INDEX.md に1行だけ追記する。形式: `- [<slug>](<file>) — <一言フック>`
- doc 本文は肥大化を避け、関心ごとに plan を分ける。1 機能 = 1 doc を基本とする。

## WIP.md（途中状態の随時保存）— 中断からの再開

plan-doc は「設計を詰めた機能」の永続ログ。一方で、plan mode に入らない ad-hoc な複数ステップ作業（設定の段階的な編集・調査の途中など）も、中断や compaction で状態が失われると再開が辛い。これを救うのが `WIP.md`。

- **置き場所**: `<project-root>/.claude/plans/WIP.md`。1 プロジェクト1ファイル（plan-doc とは別物。plan-doc は機能ごと、WIP.md は「今まさに進行中の状態」のスナップショット）。
- **書く内容**: 現タスク / 完了済み / 進行中 / 次の一手 / 未コミットの関連ファイル / 直近の決定。
- **更新タイミング（随時）**: 着手時に作成し、論理的な節目を終えるごと、そして**中断・compaction の前には必ず flush**する。状態を会話コンテキストにだけ持たせない。
- **完了したら**: 作業が決着したら WIP.md は空にする（または該当エントリを消す）。残骸を残さない。設計として残す価値があるものは plan-doc 化して INDEX.md に登録する。

### Claude Code の hook 裏打ち（他 CLI はテキストルールで運用）

`~/dotfiles/.claude/settings.json` に2つの hook を設定済み（`~/dotfiles/.claude/hooks/` に実体、`dotfilesLink.sh` で `~/.claude/hooks/` へリンク）:

- **SessionStart** (`resume-context.sh`): 起動 / 再開時に WIP.md と `git status --short` を自動で context に注入する。ルールを忘れても再開時に途中状態が必ず目に入る（クリーンかつ WIP.md 無しなら何も出さない）。WIP.md があるときは再開規律 directive（最初の応答で WIP 読了・現状・次の一手を明示し、決着済みを蒸し返さない）も併せて注入する。
- **PreCompact** (`precompact-flush.sh`): compaction 直前に「WIP.md に flush せよ」とリマインドする（未コミット変更があるときのみ）。

これらは Claude Code 専用。Antigravity / Codex では同等 hook が無いため、上記の更新タイミング規律をテキストルールとして守る。

## 継続性（セッション越え / compaction 後）— 再開時の規律

作業を再開したら、まず `<project-root>/.claude/plans/INDEX.md`（設計ログ）と `WIP.md`（途中状態）の有無を確認し、あれば関連エントリを読んでから作業に入る。これにより議論をやり直さずに済む。

- **再開した最初の応答で、WIP を読んだ旨・現状・次の一手を、動く前に明示する**。黙読はユーザーから見えず不安にさせる。SessionStart hook が WIP を注入していても、口に出さねば「読んだ」が伝わらない。
- WIP に「次の一手」があればそれを実行に移す。

### 決着済み判断の扱い

WIP.md / plan doc に「直近の決定」を明示的な見出しで残す。`AskUserQuestion` を出す前に決定リストと突き合わせる。蒸し返してよいのは、答えが記録に無いか、外向き・不可逆でユーザー承認が要る一点だけ。

## git とプライバシー

`.claude/plans/` はグローバル excludes（`~/.config/git/ignore` の `**/.claude/plans/`）で全リポジトリから自動除外される。プロジェクトの成果物 / commit を汚さない。明示的に共有したい場合のみ各自 `git add -f` する。
