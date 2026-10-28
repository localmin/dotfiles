---
name: plan-doc
description: plan mode で要件・設計の合意ができたとき（planning-workflow の手順2から呼ばれる）、または既存 plan を更新するときに使う。セッションをまたいでも compaction が走っても議論を再参照できるよう、Goals/Spec/前提と検証状況/設計/Task分割/実装の進め方/動作確認の構造化 doc をプロジェクト内（.claude/plans/）に生成し、per-project の INDEX.md に登録する。
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
3. **生成 doc を議論内容で埋める**。Goals / Spec / 前提と検証状況 / 設計 / Task 分割 / 実装の進め方 / 動作確認 の各見出しを埋める。設計は議論で詰めた内容を書く（`grilling` skill を使ったならその結果）。プロジェクトをまたいで残すべき決定があるときだけ、`domain-modeling` skill の書式で ADR（プロジェクトの `docs/adr/`）へ切り出してリンクする（小さな案件では不要）。「前提と検証状況」は、コード・設定で確認できるものを確認してから「確認済み」にし、未確認で残すものは未確認と明示する（推測を前提に混ぜない）。探して見つからなかったものは「存在しない」と断定せず、探した範囲と結果（例: 「root 直下に `*.py` なし。他の場所は未調査」）を書いて未確認のまま残す。
4. **INDEX.md のフックを調整**する。スクリプトが追記した行のフック部分を、内容を表す一言に書き換える。

## 再開時

再開時の運用（INDEX.md → 関連 doc の lazy-read、最初の応答での明示）は `planning-workflow` skill の再開規律に従う。
