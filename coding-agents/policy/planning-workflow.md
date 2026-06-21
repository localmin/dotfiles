# 計画ワークフロー（plan mode → 永続 doc）

全プロジェクト共通の進め方の詳細。CLAUDE.md の「開発ポリシー」索引から必要時に読み込む詳細 doc（`@import` ではなく on-demand Read）。

## 目的

セッションをまたいだり compaction が走っても、plan mode で詰めた要件・設計議論を失わず再参照できるようにする。議論を構造化 doc としてプロジェクト内に永続化する。

## 手順

1. **plan mode で要件を詰める**。非自明な実装・複数の妥当な方針・複数ファイルにまたがる変更は、まず plan mode に入って合意形成する。
2. **合意できたら `plan-doc` skill で構造化 doc を生成**する。skill が雛形を作るので、議論内容で各セクションを埋める。
3. **実装中も doc を更新**する。タスクの進捗・決定の変更は該当 doc に反映し、議論の現状を doc 側に持たせる（会話コンテキストに依存させない）。

## 生成 doc に含めるセクション

各 plan doc は最低限この見出しを持つ（`skills/plan-doc/template.md` が雛形）:

- **Goals** — 何を達成するか / 完了条件
- **Spec** — 仕様・制約・前提
- **Task 分割** — チェックボックスのタスクリスト
- **実装の進め方** — どのファイルをどう変えるか、再利用する既存実装、順序
- **動作確認** — どう end-to-end でテストするか（実行・MCP・テスト）

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

## 継続性（セッション越え / compaction 後）

作業を再開したら、まず `<project-root>/.claude/plans/INDEX.md` の有無を確認する。あれば「進行中の設計ログ」として関連エントリを読んでから plan に入る。これにより議論をやり直さずに済む。

## git とプライバシー

`.claude/plans/` はグローバル excludes（`~/.config/git/ignore` の `**/.claude/plans/`）で全リポジトリから自動除外される。プロジェクトの成果物 / commit を汚さない。明示的に共有したい場合のみ各自 `git add -f` する。
