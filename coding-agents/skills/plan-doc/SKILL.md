---
name: plan-doc
description: plan mode で詰めた要件・設計議論を、プロジェクト内の永続ドキュメント（.claude/plans/）として残したいときに使う。セッションをまたいでも compaction が走っても議論を再参照できるよう、Goals/Spec/Task分割/実装の進め方/動作確認の構造化 doc を生成し、per-project の INDEX.md に登録する。
---

# plan-doc

plan mode の合意内容を `<project-root>/.claude/plans/` 配下の構造化 doc に永続化する skill。詳細な運用規約は `planning-workflow` skill を参照。

## いつ使うか

- plan mode で要件・方針が固まり、それを doc として残したいとき
- 既存 plan の続きを書く / 更新するとき

## 手順

1. **対象プロジェクトルートを特定**する。ghq 管理なら `~/fragment/github.com/<owner>/<repo>`。判断できなければユーザーに確認する。
2. **雛形を生成**する: `bash ~/dotfiles/coding-agents/skills/plan-doc/scripts/new-plan.sh <slug> [<project-root>]`
   - `<project-root>` 省略時はカレントディレクトリの git トップ（`git rev-parse --show-toplevel`）を使う。
   - `<root>/.claude/plans/<YYYY-MM-DD>-<slug>.md` を template から生成し、`<root>/.claude/plans/INDEX.md` へ参照行を追記する（INDEX が無ければ作成）。
3. **生成 doc を議論内容で埋める**。Goals / Spec / 設計 / Task 分割 / 実装の進め方 / 動作確認 の各見出しを埋める。設計は grilling で詰めた内容を書き、永続する決定は ADR（`docs/adr/`）へ切り出してリンクする。
4. **INDEX.md のフックを調整**する。スクリプトが追記した行のフック部分を、内容を表す一言に書き換える。

## 再開時

作業を再開したら、まず `<project-root>/.claude/plans/INDEX.md` を読み、関連エントリだけ詳細 doc を Read してから plan に入る（全部は読まない）。
