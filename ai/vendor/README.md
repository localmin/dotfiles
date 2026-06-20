# Vendored external skills

外部リポジトリの agent skill を **pinned commit** で取得して使うための仕組み。
mizchi が APM 配布しているものを、この dotfiles の既存モデル（`ai/skills/<name>/` →
`install.sh` で Claude / Antigravity / Codex の3 CLI へ symlink）に合わせて取り込む。

## 方針

- **mechanism は tracked**（このディレクトリ: `manifest.tsv` / `fetch.sh` / `README.md`）。
- **payload は untracked**（`ai/skills/<name>/` に展開され `ai/skills/.gitignore` で除外）。
  他リポジトリのコードを自 repo に抱え込まず、upstream から都度もってくる。pin で再現性を担保。
- 出典は3層で明示: `manifest.tsv`（pin の単一ソース）/ 各 skill 内 `.upstream` / この README の表。

## 使い方

```bash
ai/vendor/fetch.sh              # 全 skill を pinned commit に (再)取得
ai/vendor/fetch.sh --if-missing # 欠けている時だけ取得 (install.sh が bootstrap で呼ぶ)
ai/install.sh                   # 取得後、3 CLI へ symlink
```

新しい環境では `ai/install.sh` が `fetch.sh --if-missing` を先に呼ぶので、
clone → `install.sh` だけで vendored skill まで揃う。

## 更新 (最新に追従)

pin は自動追従しない（環境間で版がズレないため）。最新にしたいとき:

1. `manifest.tsv` の `PIN=` を新しい commit / tag に書き換える
2. `ai/vendor/fetch.sh` を実行
3. 差分を確認して commit

## 取り込み済み skill

出典: <https://github.com/mizchi/skills>（`PIN` は `manifest.tsv` 参照 / license: MIT, repo default）

| local name | upstream path | 用途 |
|---|---|---|
| retrospective-codify | meta/retrospective-codify | learning を ast-grep ルール / CLAUDE.md / skill に codify |
| ast-grep-practice | tooling/ast-grep-practice | ast-grep を project lint として運用する how-to |
| optimizing-descriptions | meta/optimizing-descriptions | SKILL.md description の監査・リライト |
| skill-selector | meta/skill-selector | curated catalog から導入 skill を選定 |
| skill-finder | meta/skill-finder | 複数ソース横断の skill 発見 + waxa eval gate |
| empirical-prompt-tuning | meta/empirical-prompt-tuning | subagent executor による instruction の経験的改善 |
| waxa-eval | meta/waxa-eval | `waxa` CLI（skill eval）操作マニュアル |

### ランタイム依存（メモ）

`waxa-eval` / `skill-finder` は実行時に `waxa` CLI（`npx @mizchi/waxa`、要 `claude` CLI 認証）を呼ぶ。
SKILL.md はドキュメントなので vendoring だけで読めるが、eval を実際に回すには npx 経由で CLI が要る。
